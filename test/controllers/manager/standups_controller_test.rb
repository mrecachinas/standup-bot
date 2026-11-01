require "test_helper"

class Manager::StandupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @inactive_standup = standups(:inactive)
  end

  test "requires authentication" do
    get manager_standups_path

    assert_redirected_to new_session_path
  end

  test "manager sees only owned standups" do
    sign_in(@manager, "manager-access-token")

    get manager_standups_path

    assert_response :success
    assert_includes response.body, @owned_standup.name
    assert_not_includes response.body, @unowned_standup.name
  end

  test "manager layout loads Turbo runtime for frame interactions" do
    sign_in(@manager, "manager-access-token")

    get manager_standups_path

    assert_response :success
    assert_includes response.body, "@hotwired/turbo@8.0.23/dist/turbo.es2017-umd.js"
    assert_includes response.body, "sha384-2ePXINFSJiSCWUJkjFJGYdr2kyM132s7uBi9k+JISp4P+AjN9DXn4H/1enWEHu36"
    assert_includes response.body, "<turbo-frame id=\"standups_dashboard\">"
  end

  test "dashboard renders metrics, status, and navigation links" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 12, 0, 0)) do
      StandupResponse.create!(
        standup: @owned_standup,
        platform_user_id: "UDASHBOARD1",
        status: "completed",
        answers: [],
        created_at: 30.minutes.ago,
        updated_at: Time.current
      )
      StandupResponse.create!(
        standup: @owned_standup,
        platform_user_id: "UDASHBOARD2",
        status: "pending",
        answers: [],
        created_at: 20.minutes.ago
      )

      get manager_standups_path(period_days: 1)
    end

    assert_response :success
    assert_includes response.body, "Every day at 9:00 AM"
    assert_includes response.body, "2 active participants"
    # The completed response counts toward expected so the rate can't exceed 100%.
    assert_includes response.body, "20%"
    assert_includes response.body, "1 of 5 responses"
    assert_includes response.body, "Pending"
    assert_includes response.body, edit_manager_standup_path(@owned_standup)
    assert_includes response.body, manager_standup_participants_path(@owned_standup)
    assert_includes response.body, manager_standup_responses_path(@owned_standup)
    assert_includes response.body, manager_standup_analytics_path(@owned_standup)
    assert_includes response.body, manager_standup_report_path(@owned_standup)
  end

  test "new standup form starts from a template" do
    sign_in(@manager, "manager-access-token")

    get new_manager_standup_path(template: "retro")

    assert_response :success
    assert_select "a.template.is-active", text: /Friday retro/
    assert_select "input[name='standup[question_rows][]'][value='What went well this week?']"
    assert_select "input[name='standup[frequency]'][value='weekly'][checked]"
    assert_select "input[name='standup[days][]'][value='5'][checked]"
    assert_select "input[name='standup[days][]'][value='1'][checked]", count: 0
  end

  test "new standups start with the creator on the roster and their timezone in the preview" do
    standup_participants(:one).update!(cached_timezone: "America/New_York")
    @manager.link_identity!(:slack, standup_participants(:one).platform_user_id)
    sign_in(@manager, "manager-access-token")

    get new_manager_standup_path

    assert_response :success
    assert_select "input[name='standup[participants][0][platform_user_id]'][value='#{standup_participants(:one).platform_user_id}']"
    assert_select "select[name='preview_timezone'] option[selected][value='Eastern Time (US & Canada)']"
    assert_select "select[name='preview_timezone'][data-detect-timezone]", count: 0
  end

  test "new standups detect the browser timezone when the creator's is unknown" do
    sign_in(@manager, "manager-access-token")

    get new_manager_standup_path(template: "blank")

    assert_response :success
    assert_select "select[name='preview_timezone'][data-detect-timezone]"
    assert_equal %w[1 2 3 4 5], css_select("input[name='standup[days][]'][checked]").map { |input| input["value"] }
    assert_select "input[name='standup[send_time]'][value='09:30']"
  end

  test "standup overview shows stats, recent runs, and upcoming schedule" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_path(@owned_standup)

    assert_response :success
    assert_select "nav.tabs a.is-active", text: /Overview/
    assert_includes response.body, "Recent runs"
    assert_includes response.body, "Upcoming"
    Array(@owned_standup.questions).each { |question| assert_includes response.body, question }
  end

  test "visibility filter can focus active or paused standups" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.update!(active: false)

    get manager_standups_path(visibility: "active")
    assert_response :success
    assert_select "turbo-frame#standups_dashboard table", count: 0
    assert_select "turbo-frame#standups_dashboard", text: /No active standups/

    get manager_standups_path(visibility: "paused")
    assert_response :success
    assert_select "turbo-frame#standups_dashboard table", text: /#{Regexp.escape(@owned_standup.name)}/
    assert_select "turbo-frame#standups_dashboard table .badge", text: "Paused"
  end

  test "manager can update owned standup and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup.update').count", 1 do
      patch manager_standup_path(@owned_standup),
        params: { standup: { name: "Manager Updated", questions: [ "What changed?" ] } }
    end

    assert_redirected_to manager_standup_path(@owned_standup)
    assert_equal "Manager Updated", @owned_standup.reload.name

    audit_log = AuditLog.order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal @owned_standup, audit_log.auditable
    assert_equal [ "Daily Standup", "Manager Updated" ], audit_log.metadata.dig("changes", "name")
  end

  test "manager can pause and resume owned standup with audit logs" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup.pause').count", 1 do
      patch pause_manager_standup_path(@owned_standup)
    end

    assert_redirected_to manager_standups_path
    assert_equal "Daily Standup was paused.", flash[:notice]
    assert_not @owned_standup.reload.active?
    pause_log = AuditLog.order(:created_at).last
    assert_equal @manager, pause_log.actor
    assert_equal @owned_standup, pause_log.auditable
    assert_equal [ true, false ], pause_log.metadata.dig("changes", "active")

    assert_difference "AuditLog.where(action: 'standup.resume').count", 1 do
      patch resume_manager_standup_path(@owned_standup)
    end

    assert_redirected_to manager_standups_path
    assert_equal "Daily Standup was resumed.", flash[:notice]
    assert @owned_standup.reload.active?
    resume_log = AuditLog.order(:created_at).last
    assert_equal [ false, true ], resume_log.metadata.dig("changes", "active")
  end

  test "manager cannot update unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch manager_standup_path(@unowned_standup), params: { standup: { name: "Blocked" } }
    end

    assert_response :forbidden
    assert_not_equal "Blocked", @unowned_standup.reload.name
  end

  test "manager cannot pause unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch pause_manager_standup_path(@unowned_standup)
    end

    assert_response :forbidden
    assert @unowned_standup.reload.active?
  end

  test "manager cannot delete unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "Standup.count", "AuditLog.count" ] do
      delete manager_standup_path(@unowned_standup)
    end

    assert_response :forbidden
    assert Standup.exists?(@unowned_standup.id)
  end

  test "manager can create standup and becomes owner" do
    sign_in(@manager, "manager-access-token")

    assert_difference [ "Standup.count", "StandupOwnership.count", "AuditLog.where(action: 'standup.create').count" ], 1 do
      post manager_standups_path,
        params: {
          standup: {
            name: "New Manager Standup",
            platform_channel: "new-manager-standup",
            questions: [ "Any blockers?" ],
            schedule_type: "daily",
            default_hour: 9,
            default_minute: 0,
            respect_timezone: true,
            active: true
          }
        }
    end

    standup = Standup.find_by!(name: "New Manager Standup")
    assert standup.manageable_by?(@manager)
    assert_redirected_to manager_standup_path(standup)
    assert_equal "New Manager Standup was created.", flash[:notice]
  end

  test "new standup editor keeps the essentials up front and advanced settings collapsed" do
    sign_in(@manager, "manager-access-token")

    get new_manager_standup_path

    assert_response :success
    assert_includes response.body, "Create a standup"
    assert_includes response.body, "Preview schedule"
    assert_includes response.body, "standup[question_rows][]"
    assert_select "input[name='standup[participant_handles]']"
    assert_select "details#advanced:not([open])"
    assert_select "[data-schedule-summary]", text: "Weekdays at 9:30 AM, in each person's local time"
    assert_select "[data-preview-question]", text: "What did you get done yesterday?"
  end

  test "editing a weekly standup selects its day" do
    sign_in(@admin, "admin-access-token")

    get edit_manager_standup_path(@unowned_standup)

    assert_response :success
    assert_select "input[name='standup[days][]'][checked]", minimum: 1
    assert_select "[data-day-picker]:not([hidden])"
  end

  test "editing a weekly standup shows only the day it actually runs on" do
    @owned_standup.update!(schedule_type: "weekly", schedule_days: [ 1, 3 ])
    sign_in(@manager, "manager-access-token")

    get edit_manager_standup_path(@owned_standup)

    assert_equal %w[1], css_select("input[name='standup[days][]'][checked]").map { |input| input["value"] }
  end

  test "the editor works without JavaScript: blank question row and real remove checkboxes" do
    sign_in(@manager, "manager-access-token")

    get edit_manager_standup_path(@owned_standup)

    assert_equal Array(@owned_standup.questions).size + 1, css_select("[data-rows] input[name='standup[question_rows][]']").size
    assert_select "input[type=checkbox][name='standup[participants][0][_destroy]'][value='1']"
  end

  test "picking several days creates a standup that runs on all of them" do
    sign_in(@manager, "manager-access-token")

    post manager_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Three Day", schedule_type: nil, schedule_days: nil, frequency: "weekly", days: [ "", "1", "3", "5" ]).compact }

    standup = Standup.find_by!(name: "Three Day")
    assert_equal "custom", standup.schedule_type
    assert_equal [ 1, 3, 5 ], standup.schedule_days.map(&:to_i)
  end

  test "the day picker maps common choices to simple schedules" do
    sign_in(@manager, "manager-access-token")

    { "Weekday Pick" => [ %w[1 2 3 4 5], "weekdays" ], "Every Day Pick" => [ %w[0 1 2 3 4 5 6], "daily" ], "One Day Pick" => [ %w[2], "weekly" ] }.each do |name, (days, type)|
      post manager_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: name, schedule_type: nil, schedule_days: nil, frequency: "weekly", days: days).compact }
      assert_equal type, Standup.find_by!(name: name).schedule_type
    end
  end

  test "picking no days or several days every other week explains what's wrong" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "Standup.count" do
      post manager_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "No Days", schedule_type: nil, schedule_days: nil, frequency: "weekly", days: [ "" ]).compact }
    end
    assert_includes response.body, "Pick at least one day."

    assert_no_difference "Standup.count" do
      post manager_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Biweekly Many", schedule_type: nil, schedule_days: nil, frequency: "biweekly", days: %w[1 3]).compact }
    end
    assert_includes response.body, "Every other week runs on one day"
  end

  test "people can be added as a comma-separated list" do
    SlackUserResolver.any_instance.stubs(:resolve).with("@ada", fallback_name: "").returns(SlackUserResolver::ResolvedUser.new(platform_user_id: "UADA1", display_name: "Ada", cached_timezone: "UTC"))
    SlackUserResolver.any_instance.stubs(:resolve).with("@grace", fallback_name: "").returns(SlackUserResolver::ResolvedUser.new(platform_user_id: "UGRACE1", display_name: "Grace", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    post manager_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Handles", participant_handles: "@ada, @grace") }

    assert_equal %w[UADA1 UGRACE1], Standup.find_by!(name: "Handles").standup_participants.order(:platform_user_id).pluck(:platform_user_id)
  end

  test "preview renders upcoming occurrences without saving" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2025, 4, 6, 8, 0, 0)) do
      assert_no_difference "Standup.count" do
        post preview_manager_standups_path,
          params: {
            preview_timezone: "UTC",
            standup: wizard_standup_params(
              schedule_type: "weekly",
              schedule_days: [ "1" ],
              send_time: "09:15"
            )
          }
      end
    end

    assert_response :success
    assert_includes response.body, "schedule_preview"
    assert_includes response.body, "Monday, April 7, 2025 at 9:15 AM UTC"
  end

  test "manager can create standup with ordered questions participants ownership and audit metadata" do
    sign_in(@manager, "manager-access-token")

    assert_difference "Standup.count", 1 do
      assert_difference "StandupParticipant.count", 2 do
        assert_difference "StandupOwnership.count", 1 do
          assert_difference "AuditLog.where(action: 'standup.create').count", 1 do
            post manager_standups_path,
              params: {
                preview_timezone: "UTC",
                standup: wizard_standup_params(
                  name: "Wizard Standup",
                  platform_channel: "#wizard-team",
                  question_rows: [ "First question?", "Second question?", "" ],
                  participants: {
                    "0" => { platform_user_id: "uwiz001", display_name: "Wizard One", cached_timezone: "America/New_York", active: "1" },
                    "1" => { platform_user_id: "UWIZ002", display_name: "Wizard Two", cached_timezone: "Europe/London", active: "1" }
                  }
                )
              }
          end
        end
      end
    end

    standup = Standup.find_by!(name: "Wizard Standup")
    assert_redirected_to manager_standup_path(standup)
    assert_equal "wizard-team", standup.platform_channel
    assert_equal [ "First question?", "Second question?" ], standup.questions
    assert_equal 9, standup.default_hour
    assert_equal 15, standup.default_minute
    assert standup.manageable_by?(@manager)
    assert_equal [ "UWIZ001", "UWIZ002" ], standup.standup_participants.order(:platform_user_id).pluck(:platform_user_id)

    audit_log = AuditLog.where(action: "standup.create").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal [ "added", "added" ], audit_log.metadata.fetch("participants").map { |participant| participant.fetch("action") }
  end

  test "replacing the pre-filled creator row looks up the new person instead of keeping the creator's details" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("UNEWGUY", fallback_name: "")
      .returns(SlackUserResolver::ResolvedUser.new(platform_user_id: "UNEWGUY", display_name: "New Guy", cached_timezone: "Europe/Berlin"))
    sign_in(@manager, "manager-access-token")

    post manager_standups_path,
      params: {
        preview_timezone: "UTC",
        standup: wizard_standup_params(
          name: "Replaced Creator Standup",
          participants: {
            "0" => { platform_user_id: "UNEWGUY", original_slack_id: "UCREATOR", display_name: "Creator Name", cached_timezone: "America/New_York", active: "1" }
          }
        )
      }

    participant = Standup.find_by!(name: "Replaced Creator Standup").standup_participants.sole
    assert_equal "New Guy", participant.display_name
    assert_equal "Europe/Berlin", participant.cached_timezone
  end

  test "wizard resolves Slack usernames before creating participants" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("@wizard", fallback_name: "")
      .returns(SlackUserResolver::ResolvedUser.new(platform_user_id: "UWIZ003", display_name: "Wizard Resolved", cached_timezone: "America/Chicago"))
    sign_in(@manager, "manager-access-token")

    assert_difference [ "Standup.count", "StandupParticipant.count" ], 1 do
      post manager_standups_path,
        params: {
          preview_timezone: "UTC",
          standup: wizard_standup_params(
            name: "Resolved Wizard Standup",
            platform_channel: "#resolved-wizard",
            question_rows: [ "Status?", "" ],
            participants: {
              "0" => { platform_user_id: "@wizard", display_name: "", cached_timezone: "", active: "1" }
            }
          )
        }
    end

    standup = Standup.find_by!(name: "Resolved Wizard Standup")
    participant = standup.standup_participants.find_by!(platform_user_id: "UWIZ003")
    assert_redirected_to manager_standup_path(standup)
    assert_equal "Wizard Resolved", participant.display_name
    assert_equal "America/Chicago", participant.cached_timezone
  end

  test "wizard rejects invalid Slack channel and participant inputs without saving" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "Standup.count", "StandupParticipant.count", "AuditLog.count" ] do
      post manager_standups_path,
        params: {
          standup: wizard_standup_params(
            platform_channel: "bad channel",
            participants: {
              "0" => { platform_user_id: "not-a-user", display_name: "", cached_timezone: "Invalid/Zone", active: "1" }
            }
          )
        }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Channel must be a Slack channel name or ID without spaces"
    assert_includes response.body, "Participant 1 Slack ID must be a Slack user ID like U123ABC"
    assert_includes response.body, "Participant 1 name can&#39;t be blank"
    assert_includes response.body, "Participant 1 timezone is not valid"
  end

  test "manager can update question order and participant setup with audit metadata" do
    sign_in(@manager, "manager-access-token")
    removed_participant = standup_participants(:one)
    kept_participant = standup_participants(:two)

    assert_difference "StandupParticipant.count", 0 do
      assert_difference "AuditLog.where(action: 'standup.update').count", 1 do
        patch manager_standup_path(@owned_standup),
          params: {
            standup: wizard_standup_params(
              name: @owned_standup.name,
              platform_channel: @owned_standup.platform_channel,
              question_rows: [ "Third?", "First?", "Second?" ],
              participants: {
                "0" => { id: removed_participant.id, platform_user_id: removed_participant.platform_user_id, display_name: removed_participant.display_name, active: "1", _destroy: "1" },
                "1" => { id: kept_participant.id, platform_user_id: kept_participant.platform_user_id, display_name: "Jane Updated", cached_timezone: "America/Chicago", active: "1" },
                "2" => { platform_user_id: "UWIZ999", display_name: "Wizard New", cached_timezone: "UTC", active: "1" }
              }
            )
          }
      end
    end

    assert_redirected_to manager_standup_path(@owned_standup)
    @owned_standup.reload
    assert_equal [ "Third?", "First?", "Second?" ], @owned_standup.questions
    assert_not StandupParticipant.exists?(removed_participant.id)
    assert_equal "Jane Updated", kept_participant.reload.display_name
    assert @owned_standup.standup_participants.exists?(platform_user_id: "UWIZ999")

    participant_actions = AuditLog.where(action: "standup.update").order(:created_at).last.metadata.fetch("participants").map { |participant| participant.fetch("action") }
    assert_includes participant_actions, "removed"
    assert_includes participant_actions, "updated"
    assert_includes participant_actions, "added"
  end

  test "manager can delete owned standup and writes audit log" do
    sign_in(@manager, "manager-access-token")
    standup = Standup.create!(
      name: "Deletable Standup",
      platform_channel: "deletable",
      questions: [ "Question?" ],
      schedule_type: "daily",
      respect_timezone: true
    )
    standup.standup_ownerships.create!(user: @manager)

    assert_difference "Standup.count", -1 do
      assert_difference "AuditLog.where(action: 'standup.destroy').count", 1 do
        delete manager_standup_path(standup)
      end
    end

    assert_redirected_to manager_standups_path
    audit_log = AuditLog.order(:created_at).last
    assert_equal standup.id, audit_log.auditable_id
    assert_equal "Standup", audit_log.auditable_type
  end

  test "admin can manage unowned standup" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_path(@unowned_standup)

    assert_response :success
    assert_includes response.body, @unowned_standup.name
  end

  test "admin can see and resume paused standups" do
    sign_in(@admin, "admin-access-token")

    get manager_standups_path(visibility: "paused")
    assert_response :success
    assert_includes response.body, @inactive_standup.name

    assert_difference "AuditLog.where(action: 'standup.resume').count", 1 do
      patch resume_manager_standup_path(@inactive_standup)
    end

    assert_redirected_to manager_standups_path
    assert @inactive_standup.reload.active?
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end

  def wizard_standup_params(overrides = {})
    {
      name: "Wizard Params",
      platform_channel: "wizard-params",
      question_rows: [ "What changed?", "Any blockers?" ],
      schedule_type: "weekly",
      schedule_days: [ "1" ],
      monthly_day: "1",
      send_time: "09:15",
      respect_timezone: "true",
      active: "true",
      participants: {}
    }.merge(overrides)
  end
end

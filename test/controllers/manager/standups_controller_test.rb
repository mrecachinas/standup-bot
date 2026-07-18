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
        slack_id: "UDASHBOARD1",
        status: "completed",
        answers: [],
        created_at: 30.minutes.ago,
        updated_at: Time.current
      )
      StandupResponse.create!(
        standup: @owned_standup,
        slack_id: "UDASHBOARD2",
        status: "pending",
        answers: [],
        created_at: 20.minutes.ago
      )

      get manager_standups_path(period_days: 1)
    end

    assert_response :success
    assert_includes response.body, "Daily at 09:00"
    assert_includes response.body, "Participant timezones"
    assert_includes response.body, "2 active participants"
    assert_includes response.body, "25.0% (1/4)"
    assert_includes response.body, "Pending"
    assert_includes response.body, edit_manager_standup_path(@owned_standup)
    assert_includes response.body, manager_standup_participants_path(@owned_standup)
    assert_includes response.body, manager_standup_responses_path(@owned_standup)
    assert_includes response.body, manager_standup_analytics_path(@owned_standup)
    assert_includes response.body, manager_standup_report_path(@owned_standup)
  end

  test "visibility filter can focus active or paused standups" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.update!(active: false)

    get manager_standups_path(visibility: "active")
    assert_response :success
    assert_not_includes response.body, @owned_standup.name

    get manager_standups_path(visibility: "paused")
    assert_response :success
    assert_includes response.body, @owned_standup.name
    assert_includes response.body, "Paused"
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
            slack_channel: "new-manager-standup",
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

  test "new standup wizard renders schedule preview questions and participants" do
    sign_in(@manager, "manager-access-token")

    get new_manager_standup_path

    assert_response :success
    assert_includes response.body, "Create a standup"
    assert_includes response.body, "Preview schedule"
    assert_includes response.body, "standup[question_rows][]"
    assert_includes response.body, "standup[participants][0][slack_id]"
    assert_match(/data-weekday-schedule-section\s+hidden/, response.body)
    assert_includes response.body, "data-schedule-type-select"
  end

  test "weekly standup wizard initially shows weekday checkboxes" do
    sign_in(@admin, "admin-access-token")

    get edit_manager_standup_path(@unowned_standup)

    assert_response :success
    assert_match(/data-weekday-schedule-section(?!\s+hidden)/, response.body)
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
                  slack_channel: "#wizard-team",
                  question_rows: [ "First question?", "Second question?", "" ],
                  participants: {
                    "0" => { slack_id: "uwiz001", slack_name: "Wizard One", cached_timezone: "America/New_York", active: "1" },
                    "1" => { slack_id: "UWIZ002", slack_name: "Wizard Two", cached_timezone: "Europe/London", active: "1" }
                  }
                )
              }
          end
        end
      end
    end

    standup = Standup.find_by!(name: "Wizard Standup")
    assert_redirected_to manager_standup_path(standup)
    assert_equal "wizard-team", standup.slack_channel
    assert_equal [ "First question?", "Second question?" ], standup.questions
    assert_equal 9, standup.default_hour
    assert_equal 15, standup.default_minute
    assert standup.manageable_by?(@manager)
    assert_equal [ "UWIZ001", "UWIZ002" ], standup.standup_participants.order(:slack_id).pluck(:slack_id)

    audit_log = AuditLog.where(action: "standup.create").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal [ "added", "added" ], audit_log.metadata.fetch("participants").map { |participant| participant.fetch("action") }
  end

  test "wizard resolves Slack usernames before creating participants" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("@wizard", fallback_name: "")
      .returns(SlackUserResolver::ResolvedUser.new(slack_id: "UWIZ003", slack_name: "Wizard Resolved", cached_timezone: "America/Chicago"))
    sign_in(@manager, "manager-access-token")

    assert_difference [ "Standup.count", "StandupParticipant.count" ], 1 do
      post manager_standups_path,
        params: {
          preview_timezone: "UTC",
          standup: wizard_standup_params(
            name: "Resolved Wizard Standup",
            slack_channel: "#resolved-wizard",
            question_rows: [ "Status?", "" ],
            participants: {
              "0" => { slack_id: "@wizard", slack_name: "", cached_timezone: "", active: "1" }
            }
          )
        }
    end

    standup = Standup.find_by!(name: "Resolved Wizard Standup")
    participant = standup.standup_participants.find_by!(slack_id: "UWIZ003")
    assert_redirected_to manager_standup_path(standup)
    assert_equal "Wizard Resolved", participant.slack_name
    assert_equal "America/Chicago", participant.cached_timezone
  end

  test "wizard rejects invalid Slack channel and participant inputs without saving" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "Standup.count", "StandupParticipant.count", "AuditLog.count" ] do
      post manager_standups_path,
        params: {
          standup: wizard_standup_params(
            slack_channel: "bad channel",
            participants: {
              "0" => { slack_id: "not-a-user", slack_name: "", cached_timezone: "Invalid/Zone", active: "1" }
            }
          )
        }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Slack channel must be a Slack channel name or ID without spaces"
    assert_includes response.body, "Participant 1 Slack ID must look like U123ABC"
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
              slack_channel: @owned_standup.slack_channel,
              question_rows: [ "Third?", "First?", "Second?" ],
              participants: {
                "0" => { id: removed_participant.id, slack_id: removed_participant.slack_id, slack_name: removed_participant.slack_name, active: "1", _destroy: "1" },
                "1" => { id: kept_participant.id, slack_id: kept_participant.slack_id, slack_name: "Jane Updated", cached_timezone: "America/Chicago", active: "1" },
                "2" => { slack_id: "UWIZ999", slack_name: "Wizard New", cached_timezone: "UTC", active: "1" }
              }
            )
          }
      end
    end

    assert_redirected_to manager_standup_path(@owned_standup)
    @owned_standup.reload
    assert_equal [ "Third?", "First?", "Second?" ], @owned_standup.questions
    assert_not StandupParticipant.exists?(removed_participant.id)
    assert_equal "Jane Updated", kept_participant.reload.slack_name
    assert @owned_standup.standup_participants.exists?(slack_id: "UWIZ999")

    participant_actions = AuditLog.where(action: "standup.update").order(:created_at).last.metadata.fetch("participants").map { |participant| participant.fetch("action") }
    assert_includes participant_actions, "removed"
    assert_includes participant_actions, "updated"
    assert_includes participant_actions, "added"
  end

  test "manager can delete owned standup and writes audit log" do
    sign_in(@manager, "manager-access-token")
    standup = Standup.create!(
      name: "Deletable Standup",
      slack_channel: "deletable",
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
      slack_channel: "wizard-params",
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

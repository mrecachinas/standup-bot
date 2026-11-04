require "test_helper"
require_relative "../../support/teams_test_helper"

# The console's standup pages, as JSON: the editor (new/edit/create/update),
# the overview (?include=overview), the live schedule preview, and pause/resume.
class Api::StandupsConsoleTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @inactive_standup = standups(:inactive)
  end

  test "requires authentication" do
    get "/api/standups/new", as: :json
    assert_response :unauthorized

    post preview_api_standups_path, params: { standup: wizard_standup_params }, as: :json
    assert_response :unauthorized
  end

  test "new standup form starts from a template" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", params: { template: "retro" }

    assert_response :success
    body = response.parsed_body
    assert_equal "new", body["mode"]
    assert_equal "retro", body["template_key"]
    assert_equal %w[daily weekly retro], body["templates"].map { |template| template["key"] }
    retro = body["templates"].find { |template| template["key"] == "retro" }
    assert_equal "Friday retro", retro["label"]
    assert_equal 3, retro["question_count"]
    assert_includes body["question_rows"], "What went well this week?"
    assert_equal "", body["question_rows"].last
    assert_equal({ "frequency" => "weekly", "days" => [ 5 ] }, body.dig("standup", "schedule_picker"))
    assert_nil body.dig("standup", "id")
  end

  test "new standups start with the creator on the roster and their timezone in the preview" do
    standup_participants(:one).update!(cached_timezone: "America/New_York")
    @manager.link_identity!(:slack, standup_participants(:one).platform_user_id)

    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", as: :json

    assert_response :success
    body = response.parsed_body
    creator = body["participant_rows"].sole
    assert_equal standup_participants(:one).platform_user_id, creator["platform_user_id"]
    assert_equal creator["platform_user_id"], creator["original_platform_user_id"]
    assert_nil creator["id"]
    assert_equal "Eastern Time (US & Canada)", body["default_preview_timezone"]
    assert_equal "Eastern Time (US & Canada)", body["preview_timezone"]
    assert_equal false, body["detect_preview_timezone"]
  end

  test "new standups detect the browser timezone when the creator's is unknown" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", params: { template: "blank" }

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["detect_preview_timezone"]
    assert_nil body["default_preview_timezone"]
    assert_equal "UTC", body["preview_timezone"]
    assert_equal [ 1, 2, 3, 4, 5 ], body.dig("standup", "schedule_picker", "days")
    assert_equal "09:30", body["send_time"]
    assert_equal [ "" ], body["question_rows"]
    assert_empty body["participant_rows"]
  end

  test "new standup editor returns everything the form renders" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "daily", body["template_key"]
    assert_equal false, body["advanced_open"]
    assert_equal "Weekdays at 9:30 AM, in each person's local time", body.dig("standup", "schedule_sentence")
    assert_equal "What did you get done yesterday?", body.dig("message_preview", "first_question")
    assert_equal 3, body.dig("message_preview", "question_count")
    assert_equal "9:30 AM", body.dig("message_preview", "time")
    assert_includes body.dig("message_preview", "hint"), "Slack DM"
    assert_equal "search", body.dig("channel", "input")
    assert_equal "slack", body.dig("platform", "key")
    assert_includes body["platform_options"].map { |option| option["key"] }, "slack"
    assert body["platform_options"].all? { |option| option.key?("label") && option.key?("icon") }
    assert_nil body["channel_options"]
    assert_equal %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday], body["weekday_options"].map { |day| day["label"] }
    assert_equal "Mon", body["weekday_options"].first["short_label"]
    assert_equal 1, body["weekday_options"].first["value"]
    assert_equal %w[weekly biweekly monthly], body["frequency_options"].map { |option| option["value"] }
    assert_includes body["day_presets"], { "label" => "Weekdays", "days" => [ 1, 2, 3, 4, 5 ] }
    suggestion = body["question_suggestions"].find { |item| item["text"] == "What did you get done yesterday?" }
    assert suggestion["used"]
    assert_includes body["time_zone_options"], { "name" => "Eastern Time (US & Canada)", "iana" => "America/New_York" }
    assert_equal 4, body.dig("schedule_preview", "occurrences").size
    assert_nil body.dig("schedule_preview", "error")
    occurrence = body.dig("schedule_preview", "occurrences").first
    assert_equal %w[date label scheduled_at time weekday], occurrence.keys.sort
  end

  test "an admin's token gets a form without a creator row" do
    get "/api/standups/new", headers: token_headers, as: :json

    assert_response :success
    assert_empty response.parsed_body["participant_rows"]
    assert_equal true, response.parsed_body["detect_preview_timezone"]
  end

  test "editing returns the roster and a blank question row" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/#{@owned_standup.id}/edit", as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "edit", body["mode"]
    assert_equal true, body["platform_locked"]
    assert_equal false, body["show_platform_picker"]
    assert_equal Array(@owned_standup.questions).size + 1, body["question_rows"].size
    assert_equal @owned_standup.standup_participants.count, body["participant_rows"].size
    assert body["participant_rows"].all? { |row| row["id"].present? && row["destroy"] == false }
    inactive_row = body["participant_rows"].find { |row| row["id"] == standup_participants(:inactive).id }
    assert_equal "inactive", inactive_row["meta"]
    assert_equal "Names and timezones come from Slack.", body["participants_hint"]
  end

  test "editing a weekly standup selects its day" do
    sign_in(@admin, "admin-access-token")

    get "/api/standups/#{@unowned_standup.id}/edit", as: :json

    assert_response :success
    assert_equal [ 1 ], response.parsed_body.dig("standup", "schedule_picker", "days")
  end

  test "editing a weekly standup shows only the day it actually runs on" do
    @owned_standup.update!(schedule_type: "weekly", schedule_days: [ 1, 3 ])

    sign_in(@manager, "manager-access-token")

    get "/api/standups/#{@owned_standup.id}/edit", as: :json

    assert_equal [ 1 ], response.parsed_body.dig("standup", "schedule_picker", "days")
  end

  test "a manager can't open the editor for a standup they don't manage" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/#{@unowned_standup.id}/edit", as: :json

    assert_response :forbidden
  end

  test "standup overview shows stats, recent runs, and upcoming schedule" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.standup_schedule_exceptions.create!(exception_type: "holiday", original_date: 10.days.from_now.to_date, reason: "Offsite")
    StandupResponse.create!(
      standup: @owned_standup,
      platform_user_id: standup_participants(:one).platform_user_id,
      standup_date: Date.current,
      status: "completed",
      answers: [ { "question" => "What did you do yesterday?", "answer" => "Shipped it" } ]
    )

    get api_standup_path(@owned_standup), params: { include: "overview" }

    assert_response :success
    body = response.parsed_body
    assert_equal Array(@owned_standup.questions), body.dig("standup", "questions")
    assert_equal "Active", body.dig("standup", "status_label")
    overview = body["overview"]
    assert_equal %w[
      average_response_time completion latest_run more_participants_count next_run participant_counts participants
      period_days runs runs_have_pending schedule_exceptions sidebar_participants summary upcoming
    ], overview.keys.sort
    assert_equal 14, overview["period_days"]
    assert_equal({ "total" => 4, "active" => 2, "inactive" => 2 }, overview["participant_counts"])
    assert_equal 4, overview["participants"].size
    assert overview["participants"].first.key?("timezone_cache_status")
    assert_equal 2, overview["sidebar_participants"].size
    assert_equal 4, overview.dig("upcoming", "occurrences").size
    assert_equal "UTC", overview.dig("upcoming", "preview_timezone")
    assert_match(/\A9:00 AM in each person's timezone\z/, overview.dig("next_run", "sub_label"))
    assert overview.dig("next_run", "scheduled_at").present?
    assert_equal "Holiday", overview["schedule_exceptions"].sole["label"]
    latest = overview.dig("latest_run", "responses").sole
    assert_equal "John Doe", latest["display_name"]
    assert_equal "Completed", latest["status_label"]
    assert_equal "success", latest["status_tone"]
    assert_equal [ { "question" => "What did you do yesterday?", "answer" => "Shipped it" } ], latest["answers"]
    assert overview["runs"].all? { |run| run.key?("date") && run.key?("completion_rate") }
    assert overview.dig("summary", "expected_responses").is_a?(Integer)
    assert overview["completion"].key?("label")
  end

  test "the overview previews a local-time standup in the timezone most of its people are in" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.standup_participants.create!(platform_user_id: "UNEWYORK1", display_name: "Nia", active: true)
    active = @owned_standup.standup_participants.where(active: true).order(:id).to_a
    active.first.update!(cached_timezone: "Europe/London")
    active.drop(1).each { |participant| participant.update!(cached_timezone: "America/New_York") }
    # Inactive people don't count, even when there are more of them.
    @owned_standup.standup_participants.where(active: false).update_all(cached_timezone: "Asia/Tokyo")
    @owned_standup.standup_participants.create!(platform_user_id: "UTOKYO2", display_name: "Kai", active: false, cached_timezone: "Asia/Tokyo")

    get api_standup_path(@owned_standup), params: { include: "overview" }

    assert_equal "Eastern Time (US & Canada)", response.parsed_body.dig("overview", "upcoming", "preview_timezone")

    @owned_standup.update!(respect_timezone: false)
    get api_standup_path(@owned_standup), params: { include: "overview" }

    assert_equal "UTC", response.parsed_body.dig("overview", "upcoming", "preview_timezone")
  end

  test "the overview keeps a participant timezone stored by its Rails name" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.standup_participants.where(active: true).update_all(cached_timezone: "Eastern Time (US & Canada)")

    get api_standup_path(@owned_standup), params: { include: "overview" }

    assert_equal "Eastern Time (US & Canada)", response.parsed_body.dig("overview", "upcoming", "preview_timezone")
  end

  test "the overview of a paused standup says so" do
    sign_in(@admin, "admin-access-token")

    get api_standup_path(@inactive_standup), params: { include: "overview", preview_timezone: "Eastern Time (US & Canada)" }

    assert_response :success
    overview = response.parsed_body["overview"]
    assert_equal "Paused", overview.dig("next_run", "label")
    assert_equal "Resume to schedule runs", overview.dig("next_run", "sub_label")
    assert overview.dig("upcoming", "paused")
    assert_equal "Eastern Time (US & Canada)", overview.dig("upcoming", "preview_timezone")
  end

  test "show without include keeps the admin API's shape" do
    get api_standup_path(@owned_standup), headers: token_headers, as: :json

    assert_response :success
    assert_equal [ "standup" ], response.parsed_body.keys
  end

  test "manager can update owned standup and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup.update').count", 1 do
      patch api_standup_path(@owned_standup),
        params: { standup: { name: "Manager Updated", questions: [ "What changed?" ] } },
        as: :json
    end

    assert_response :success
    assert_equal "Manager Updated was updated.", response.parsed_body["notice"]
    assert_equal "Manager Updated", response.parsed_body.dig("standup", "name")
    assert_equal "Manager Updated", @owned_standup.reload.name

    audit_log = AuditLog.order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal @owned_standup, audit_log.auditable
    assert_equal [ "Daily Standup", "Manager Updated" ], audit_log.metadata.dig("changes", "name")
    assert_not audit_log.metadata.key?("participants")
  end

  test "saving settings without people leaves the people alone" do
    sign_in(@manager, "manager-access-token")
    before = @owned_standup.standup_participants.order(:id).pluck(:id, :active)

    patch api_standup_path(@owned_standup), params: { standup: { name: "Renamed", question_rows: [ "What changed?" ] } }, as: :json

    assert_response :success
    assert_equal before, @owned_standup.standup_participants.order(:id).pluck(:id, :active)
  end

  test "manager can pause and resume owned standup with audit logs" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup.pause').count", 1 do
      patch pause_api_standup_path(@owned_standup), as: :json
    end

    assert_response :success
    assert_equal "Daily Standup was paused.", response.parsed_body["notice"]
    assert_equal false, response.parsed_body.dig("standup", "active")
    assert_equal "Paused", response.parsed_body.dig("standup", "status_label")
    assert_not @owned_standup.reload.active?
    pause_log = AuditLog.order(:created_at).last
    assert_equal @manager, pause_log.actor
    assert_equal @owned_standup, pause_log.auditable
    assert_equal [ true, false ], pause_log.metadata.dig("changes", "active")

    assert_difference "AuditLog.where(action: 'standup.resume').count", 1 do
      patch resume_api_standup_path(@owned_standup), as: :json
    end

    assert_response :success
    assert_equal "Daily Standup was resumed.", response.parsed_body["notice"]
    assert @owned_standup.reload.active?
    resume_log = AuditLog.order(:created_at).last
    assert_equal [ false, true ], resume_log.metadata.dig("changes", "active")
  end

  test "pausing a paused standup does nothing" do
    sign_in(@admin, "admin-access-token")

    assert_no_difference "AuditLog.count" do
      patch pause_api_standup_path(@inactive_standup), as: :json
    end

    assert_response :success
    assert_nil response.parsed_body["notice"]
    assert_equal false, response.parsed_body.dig("standup", "active")
  end

  test "a bearer token pauses a standup, audited as its user" do
    patch pause_api_standup_path(@owned_standup), headers: token_headers, as: :json

    assert_response :success
    audit_log = AuditLog.where(action: "standup.pause").order(:created_at).last
    assert_equal @admin, audit_log.actor
  end

  test "manager cannot update unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch api_standup_path(@unowned_standup), params: { standup: { name: "Blocked" } }, as: :json
    end

    assert_response :forbidden
    assert_not_equal "Blocked", @unowned_standup.reload.name
  end

  test "manager cannot pause or resume unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch pause_api_standup_path(@unowned_standup), as: :json
      assert_response :forbidden
      patch resume_api_standup_path(@unowned_standup), as: :json
      assert_response :forbidden
    end

    assert @unowned_standup.reload.active?
  end

  test "manager cannot delete unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "Standup.count", "AuditLog.count" ] do
      delete api_standup_path(@unowned_standup), as: :json
    end

    assert_response :forbidden
    assert Standup.exists?(@unowned_standup.id)
  end

  test "manager cannot see the overview of an unowned standup" do
    sign_in(@manager, "manager-access-token")

    get api_standup_path(@unowned_standup), params: { include: "overview" }

    assert_response :forbidden
  end

  test "manager can create standup and becomes owner" do
    sign_in(@manager, "manager-access-token")

    assert_difference [ "Standup.count", "StandupOwnership.count", "AuditLog.where(action: 'standup.create').count" ], 1 do
      post api_standups_path, params: { standup: admin_standup_params(name: "New Manager Standup") }, as: :json
    end

    assert_response :created
    assert_equal "New Manager Standup was created.", response.parsed_body["notice"]
    standup = Standup.find_by!(name: "New Manager Standup")
    assert_equal standup.id, response.parsed_body.dig("standup", "id")
    assert standup.manageable_by?(@manager)
    assert_equal "owner", standup.standup_ownerships.sole.role
    assert_equal @manager, standup.standup_ownerships.sole.user
  end

  test "an admin's session creates standups without an ownership" do
    sign_in(@admin, "admin-access-token")

    assert_difference "Standup.count", 1 do
      assert_no_difference "StandupOwnership.count" do
        post api_standups_path, params: { standup: admin_standup_params(name: "Admin Session Standup") }, as: :json
      end
    end

    assert_response :created
    assert_equal @admin, AuditLog.where(action: "standup.create").order(:created_at).last.actor
  end

  test "admin-shaped token create keeps the script semantics" do
    assert_difference "Standup.count", 1 do
      assert_no_difference [ "StandupOwnership.count", "StandupParticipant.count" ] do
        post api_standups_path,
          params: { standup: admin_standup_params(name: "Token Standup", questions: [ "Two\nlines?", "Second?" ], schedule_type: "weekly", schedule_days: [ 2 ]) },
          headers: token_headers,
          as: :json
      end
    end

    assert_response :created
    body = response.parsed_body
    standup = Standup.find_by!(name: "Token Standup")
    # Script requests keep their questions as sent; the editor would split lines.
    assert_equal [ "Two\nlines?", "Second?" ], standup.questions
    assert_equal [ 2 ], standup.schedule_days.map(&:to_i)
    assert_equal 9, standup.default_hour
    assert_equal 0, standup.default_minute
    assert_equal "Token Standup", body.dig("standup", "name")
    assert body["standup"].key?("participants_count")

    audit_log = AuditLog.where(action: "standup.create").order(:created_at).last
    assert_equal @admin, audit_log.actor
    assert_equal "Token Standup", audit_log.metadata.dig("attributes", "name")
    assert_equal "slack", audit_log.metadata.dig("attributes", "platform")
    assert_not audit_log.metadata.key?("participants")
  end

  test "admin-shaped validation errors keep the errors array and add field errors" do
    post api_standups_path,
      params: { standup: admin_standup_params(name: "", platform_channel: "") },
      headers: token_headers,
      as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_includes body["errors"], "Name can't be blank"
    assert_includes body["field_errors"]["name"], "can't be blank"
  end

  test "picking several days creates a standup that runs on all of them" do
    sign_in(@manager, "manager-access-token")

    post api_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Three Day", schedule_type: nil, schedule_days: nil, frequency: "weekly", days: [ "", "1", "3", "5" ]).compact }, as: :json

    assert_response :created
    standup = Standup.find_by!(name: "Three Day")
    assert_equal "custom", standup.schedule_type
    assert_equal [ 1, 3, 5 ], standup.schedule_days.map(&:to_i)
  end

  test "the day picker maps common choices to simple schedules" do
    sign_in(@manager, "manager-access-token")

    { "Weekday Pick" => [ %w[1 2 3 4 5], "weekdays" ], "Every Day Pick" => [ %w[0 1 2 3 4 5 6], "daily" ], "One Day Pick" => [ %w[2], "weekly" ] }.each do |name, (days, type)|
      post api_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: name, schedule_type: nil, schedule_days: nil, frequency: "weekly", days: days).compact }, as: :json
      assert_response :created
      assert_equal type, Standup.find_by!(name: name).schedule_type
    end
  end

  test "picking no days or several days every other week explains what's wrong" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "Standup.count" do
      post api_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "No Days", schedule_type: nil, schedule_days: nil, frequency: "weekly", days: [ "" ]).compact }, as: :json
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Pick at least one day."
    assert_includes response.parsed_body.dig("field_errors", "base"), "Pick at least one day."

    assert_no_difference "Standup.count" do
      post api_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Biweekly Many", schedule_type: nil, schedule_days: nil, frequency: "biweekly", days: %w[1 3]).compact }, as: :json
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Every other week runs on one day. Pick a single day."
  end

  test "people can be added as a comma-separated list" do
    ChatUserResolver.any_instance.stubs(:resolve).with("@ada", fallback_name: "").returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UADA1", display_name: "Ada", cached_timezone: "UTC"))
    ChatUserResolver.any_instance.stubs(:resolve).with("@grace", fallback_name: "").returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UGRACE1", display_name: "Grace", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    post api_standups_path, params: { preview_timezone: "UTC", standup: wizard_standup_params(name: "Handles", participant_handles: "@ada, @grace") }, as: :json

    assert_response :created
    assert_equal %w[UADA1 UGRACE1], Standup.find_by!(name: "Handles").standup_participants.order(:platform_user_id).pluck(:platform_user_id)
  end

  test "preview returns upcoming occurrences without saving" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2025, 4, 6, 8, 0, 0)) do
      assert_no_difference "Standup.count" do
        post preview_api_standups_path,
          params: {
            preview_timezone: "UTC",
            standup: wizard_standup_params(schedule_type: "weekly", schedule_days: [ "1" ], send_time: "09:15")
          },
          as: :json
      end
    end

    assert_response :success
    body = response.parsed_body
    assert_equal %w[empty_message error occurrences preview_timezone], body.keys.sort
    assert_nil body["error"]
    assert_equal "UTC", body["preview_timezone"]
    first = body["occurrences"].first
    assert_equal "Monday, April 7, 2025 at 9:15 AM UTC", first["label"]
    assert_equal "2025-04-07T09:15:00Z", first["scheduled_at"]
    assert_equal "Monday", first["weekday"]
    assert_equal "9:15 AM UTC", first["time"]
  end

  test "preview explains a schedule it can't show" do
    sign_in(@manager, "manager-access-token")

    patch preview_api_standups_path, params: { standup: wizard_standup_params(schedule_type: nil, schedule_days: nil, frequency: "weekly", days: [ "" ]).compact }, as: :json

    assert_response :success
    assert_equal "Pick at least one day.", response.parsed_body["error"]
    assert_empty response.parsed_body["occurrences"]

    post preview_api_standups_path, params: { standup: wizard_standup_params(send_time: "nope") }, as: :json

    assert_equal "Fix recurrence and send time to preview upcoming occurrences.", response.parsed_body["error"]
  end

  test "manager can create standup with ordered questions participants ownership and audit metadata" do
    sign_in(@manager, "manager-access-token")

    assert_difference "Standup.count", 1 do
      assert_difference "StandupParticipant.count", 2 do
        assert_difference "StandupOwnership.count", 1 do
          assert_difference "AuditLog.where(action: 'standup.create').count", 1 do
            post api_standups_path,
              params: {
                preview_timezone: "UTC",
                standup: wizard_standup_params(
                  name: "Wizard Standup",
                  platform_channel: "#wizard-team",
                  question_rows: [ "First question?", "Second question?", "" ],
                  reminder_enabled: true,
                  reminder_after_minutes: 45,
                  max_reminders: 2,
                  participants: [
                    { platform_user_id: "uwiz001", display_name: "Wizard One", cached_timezone: "America/New_York", active: "1" },
                    { platform_user_id: "UWIZ002", display_name: "Wizard Two", cached_timezone: "Europe/London", active: "1" }
                  ]
                )
              },
              as: :json
          end
        end
      end
    end

    assert_response :created
    standup = Standup.find_by!(name: "Wizard Standup")
    assert_equal "wizard-team", standup.platform_channel
    assert_equal [ "First question?", "Second question?" ], standup.questions
    assert_equal 9, standup.default_hour
    assert_equal 15, standup.default_minute
    assert_equal 45, standup.reminder_after_minutes
    assert_equal 2, standup.max_reminders
    assert standup.manageable_by?(@manager)
    assert_equal [ "UWIZ001", "UWIZ002" ], standup.standup_participants.order(:platform_user_id).pluck(:platform_user_id)
    assert_equal 2, response.parsed_body.dig("standup", "participants_count")

    audit_log = AuditLog.where(action: "standup.create").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal [ "added", "added" ], audit_log.metadata.fetch("participants").map { |participant| participant.fetch("action") }
  end

  test "replacing the pre-filled creator row looks up the new person instead of keeping the creator's details" do
    ChatUserResolver.any_instance.expects(:resolve)
      .with("UNEWGUY", fallback_name: "")
      .returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UNEWGUY", display_name: "New Guy", cached_timezone: "Europe/Berlin"))
    sign_in(@manager, "manager-access-token")

    post api_standups_path,
      params: {
        preview_timezone: "UTC",
        standup: wizard_standup_params(
          name: "Replaced Creator Standup",
          participants: [
            { platform_user_id: "UNEWGUY", original_platform_user_id: "UCREATOR", display_name: "Creator Name", cached_timezone: "America/New_York", active: "1" }
          ]
        )
      },
      as: :json

    assert_response :created
    participant = Standup.find_by!(name: "Replaced Creator Standup").standup_participants.sole
    assert_equal "New Guy", participant.display_name
    assert_equal "Europe/Berlin", participant.cached_timezone
  end

  test "wizard resolves Slack usernames before creating participants" do
    ChatUserResolver.any_instance.expects(:resolve)
      .with("@wizard", fallback_name: "")
      .returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UWIZ003", display_name: "Wizard Resolved", cached_timezone: "America/Chicago"))
    sign_in(@manager, "manager-access-token")

    assert_difference [ "Standup.count", "StandupParticipant.count" ], 1 do
      post api_standups_path,
        params: {
          preview_timezone: "UTC",
          standup: wizard_standup_params(
            name: "Resolved Wizard Standup",
            platform_channel: "#resolved-wizard",
            question_rows: [ "Status?", "" ],
            participants: [ { platform_user_id: "@wizard", display_name: "", cached_timezone: "", active: "1" } ]
          )
        },
        as: :json
    end

    assert_response :created
    participant = Standup.find_by!(name: "Resolved Wizard Standup").standup_participants.find_by!(platform_user_id: "UWIZ003")
    assert_equal "Wizard Resolved", participant.display_name
    assert_equal "America/Chicago", participant.cached_timezone
  end

  test "wizard rejects invalid Slack channel and participant inputs without saving" do
    ChatUserResolver.any_instance.stubs(:resolve).raises(ChatUserResolver::ResolutionError, "Couldn't find not-a-user in Slack.")
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "Standup.count", "StandupParticipant.count", "AuditLog.count" ] do
      post api_standups_path,
        params: {
          standup: wizard_standup_params(
            platform_channel: "bad channel",
            participants: [ { platform_user_id: "not-a-user", display_name: "", cached_timezone: "Invalid/Zone", active: "1" } ]
          )
        },
        as: :json
    end

    assert_response :unprocessable_entity
    errors = response.parsed_body["errors"]
    assert_includes errors, "Channel must be a Slack channel name or ID without spaces"
    assert_includes errors, "Participant 1: Couldn't find not-a-user in Slack."
    assert_includes errors, "Participant 1 Slack ID must be a Slack user ID like U123ABC"
    assert_includes errors, "Participant 1 name can't be blank"
    assert_includes errors, "Participant 1 timezone is not valid"
    assert_includes response.parsed_body.dig("field_errors", "base"), "Participant 1 timezone is not valid"
  end

  test "manager can update question order and participant setup with audit metadata" do
    sign_in(@manager, "manager-access-token")
    removed_participant = standup_participants(:one)
    kept_participant = standup_participants(:two)

    assert_difference "StandupParticipant.count", 0 do
      assert_difference "AuditLog.where(action: 'standup.update').count", 1 do
        patch api_standup_path(@owned_standup),
          params: {
            standup: wizard_standup_params(
              name: @owned_standup.name,
              platform_channel: @owned_standup.platform_channel,
              question_rows: [ "Third?", "First?", "Second?" ],
              participants: [
                { id: removed_participant.id, platform_user_id: removed_participant.platform_user_id, display_name: removed_participant.display_name, active: "1", _destroy: "1" },
                { id: kept_participant.id, platform_user_id: kept_participant.platform_user_id, display_name: "Jane Updated", cached_timezone: "America/Chicago", active: "1" },
                { platform_user_id: "UWIZ999", display_name: "Wizard New", cached_timezone: "UTC", active: "1" }
              ]
            )
          },
          as: :json
      end
    end

    assert_response :success
    assert_equal "Daily Standup was updated.", response.parsed_body["notice"]
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

  test "people rows can't duplicate someone already in the standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupParticipant.count" do
      patch api_standup_path(@owned_standup),
        params: { standup: { participants: [ { platform_user_id: standup_participants(:one).platform_user_id, display_name: "Again", active: "1" } ] } },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Participant 1 Slack ID is already in this standup"
  end

  test "people rows must belong to the standup" do
    sign_in(@manager, "manager-access-token")

    patch api_standup_path(@owned_standup),
      params: { standup: { participants: [ { id: standup_participants(:three).id, platform_user_id: "U345678", display_name: "Alice", active: "1" } ] } },
      as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Participant 1 could not be found for this standup"
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
        delete api_standup_path(standup), as: :json
      end
    end

    assert_response :no_content
    audit_log = AuditLog.order(:created_at).last
    assert_equal standup.id, audit_log.auditable_id
    assert_equal "Standup", audit_log.auditable_type
    assert_equal @manager, audit_log.actor
  end

  test "admin can manage unowned standup" do
    sign_in(@admin, "admin-access-token")

    get api_standup_path(@unowned_standup), params: { include: "overview" }

    assert_response :success
    assert_equal @unowned_standup.name, response.parsed_body.dig("standup", "name")
  end

  test "admin can resume paused standups" do
    sign_in(@admin, "admin-access-token")

    assert_difference "AuditLog.where(action: 'standup.resume').count", 1 do
      patch resume_api_standup_path(@inactive_standup), as: :json
    end

    assert_response :success
    assert @inactive_standup.reload.active?
    assert_equal "Archived Standup was resumed.", response.parsed_body["notice"]
  end

  private

  def admin_standup_params(overrides = {})
    {
      name: "Admin Shaped",
      platform_channel: "admin-shaped",
      questions: [ "Any blockers?" ],
      schedule_type: "daily",
      default_hour: 9,
      default_minute: 0,
      respect_timezone: true,
      active: true
    }.merge(overrides)
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
      participants: []
    }.merge(overrides)
  end
end

# The editor with Microsoft Teams turned on alongside Slack.
class Api::TeamsStandupsConsoleTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    enable_teams!
    @manager = users(:manager)
    TeamsIntegrationService.any_instance.stubs(:discover_channels).returns(
      ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ], message: "Found 1 Microsoft Teams channel(s).")
    )
  end

  test "new standup offers both platforms and a Teams channel picker" do
    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", params: { platform: "teams" }

    assert_response :success
    body = response.parsed_body
    assert_equal %w[slack teams], body["platform_options"].map { |option| option["key"] }
    assert_equal [ "Slack", "Microsoft Teams" ], body["platform_options"].map { |option| option["label"] }
    assert_equal %w[hash people], body["platform_options"].map { |option| option["icon"] }
    assert body["show_platform_picker"]
    assert_equal "teams", body.dig("standup", "platform")
    assert_equal "select", body.dig("channel", "input")
    assert_equal [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ], body.dig("channel", "choices")
    assert_equal true, body.dig("channel_options", "success")
    assert_equal TEAMS_CHANNEL, body.dig("channel_options", "records").sole["id"]
    assert_includes body.dig("message_preview", "hint"), "Asked one at a time in a Microsoft Teams DM"
  end

  test "falls back to a typed channel ID when Teams channels can't be listed" do
    TeamsIntegrationService.any_instance.stubs(:discover_channels).returns(
      ChatIntegrationService::Result.new(status: "error", records: [], message: "Teams isn't set up yet.")
    )

    sign_in(@manager, "manager-access-token")

    get "/api/standups/new", params: { platform: "teams" }

    body = response.parsed_body
    assert_equal "text", body.dig("channel", "input")
    assert_equal "Teams isn't set up yet.", body.dig("channel", "hint")
    assert_equal false, body.dig("channel_options", "success")
  end

  test "creates a Teams standup with Teams participants" do
    sign_in(@manager, "manager-access-token")

    assert_difference "Standup.count", 1 do
      post api_standups_path, params: {
        standup: {
          name: "Teams Daily",
          platform: "teams",
          platform_channel: TEAMS_CHANNEL,
          platform_channel_name: "Engineering › Standup",
          question_rows: [ "What changed?" ],
          schedule_type: "weekly",
          schedule_days: [ "1" ],
          send_time: "09:15",
          respect_timezone: "true",
          active: "true",
          participants: [ { platform_user_id: TEAMS_USER_ID.upcase, display_name: "Tess Teams", active: "1" } ]
        }
      }, as: :json
    end

    assert_response :created
    standup = Standup.order(:id).last
    assert_equal "teams", standup.platform
    assert_equal "Engineering › Standup", standup.channel_reference
    assert_equal [ TEAMS_USER_ID ], standup.standup_participants.pluck(:platform_user_id)
    assert_equal "Microsoft Teams", response.parsed_body.dig("standup", "platform_label")
    assert_equal "Engineering › Standup", response.parsed_body.dig("standup", "platform_channel_name")
  end

  test "Teams people rows are checked with Teams wording" do
    sign_in(@manager, "manager-access-token")

    post api_standups_path, params: {
      standup: {
        name: "Teams Bad People",
        platform: "teams",
        platform_channel: TEAMS_CHANNEL,
        question_rows: [ "What changed?" ],
        frequency: "weekly",
        days: [ "1" ],
        send_time: "09:15",
        participants: [ { platform_user_id: TEAMS_USER_ID, display_name: "", cached_timezone: "Nowhere/Zone", active: "1" } ]
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Participant 1 timezone is not valid"
  end

  test "editing can't move a standup to another platform" do
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    sign_in(@manager, "manager-access-token")

    patch api_standup_path(standup), params: { standup: { name: "Renamed", platform: "slack" } }, as: :json

    assert_response :unprocessable_entity
    assert_equal "teams", standup.reload.platform
    assert_equal "Teams Standup", standup.name

    patch api_standup_path(standup), params: { standup: { name: "Renamed" } }, as: :json

    assert_response :success
    assert_equal "Renamed", standup.reload.name
    assert_equal "teams", standup.platform
  end

  test "editing keeps the current channel selectable when discovery doesn't list it" do
    standup = create_teams_standup!
    standup.update!(platform_channel: "#{TEAMS_TEAM_ID}|19:private@thread.tacv2", platform_channel_name: "Engineering › Private")
    standup.standup_ownerships.create!(user: @manager)

    sign_in(@manager, "manager-access-token")

    get "/api/standups/#{standup.id}/edit", as: :json

    assert_response :success
    channel = response.parsed_body["channel"]
    assert_equal "#{TEAMS_TEAM_ID}|19:private@thread.tacv2", channel["value"]
    assert_equal({ "id" => "#{TEAMS_TEAM_ID}|19:private@thread.tacv2", "label" => "Engineering › Private" }, channel["choices"].first)
    assert_equal 2, channel["choices"].size
    assert_equal false, response.parsed_body["show_platform_picker"]
  end

  test "channel options list Teams channels, private ones only for admins" do
    TeamsIntegrationService.any_instance.unstub(:discover_channels)
    TeamsIntegrationService.any_instance.expects(:discover_channels)
      .with(query: nil, limit: ChatIntegrationService::MAX_LIMIT, include_private: false)
      .returns(ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ], message: "Found 1."))
    sign_in(@manager, "manager-access-token")

    get channel_options_api_standups_path(platform: "teams"), as: :json

    assert_response :success
    assert_equal({ "platform" => "teams", "records" => [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ], "success" => true, "message" => "Found 1.", "action" => nil }, response.parsed_body)

    TeamsIntegrationService.any_instance.expects(:discover_channels)
      .with(query: nil, limit: ChatIntegrationService::MAX_LIMIT, include_private: true)
      .returns(ChatIntegrationService::Result.new(status: "ok", records: [], message: "Found 0."))
    sign_in(users(:admin), "admin-access-token")

    get channel_options_api_standups_path(platform: "teams"), as: :json
    assert_response :success
  end

  test "channel options reject unknown platforms and need a manager" do
    get channel_options_api_standups_path(platform: "teams"), as: :json
    assert_response :unauthorized

    sign_in(@manager, "manager-access-token")
    get channel_options_api_standups_path(platform: "irc"), as: :json
    assert_response :unprocessable_entity
  end

  test "an admin's token can list channel options including private ones" do
    TeamsIntegrationService.any_instance.unstub(:discover_channels)
    TeamsIntegrationService.any_instance.expects(:discover_channels)
      .with(query: nil, limit: ChatIntegrationService::MAX_LIMIT, include_private: true)
      .returns(ChatIntegrationService::Result.new(status: "ok", records: [], message: "Found 0."))

    get channel_options_api_standups_path(platform: "teams"), headers: token_headers, as: :json

    assert_response :success
  end

  test "channel options search Slack channels by name for the picker" do
    SlackIntegrationService.any_instance.expects(:discover_channels)
      .with(query: "standup", limit: ChatIntegrationService::MAX_LIMIT, include_private: false)
      .returns(ChatIntegrationService::Result.new(
        status: "ok",
        records: [ { "id" => "C0STANDUP", "name" => "standup-bot-test", "label" => "#standup-bot-test", "is_private" => false, "is_member" => true, "num_members" => 2 } ],
        message: "Found 1 Slack channel(s)."
      ))
    sign_in(@manager, "manager-access-token")

    get channel_options_api_standups_path, params: { platform: "slack", query: "#standup" }

    assert_response :success
    assert_equal(
      {
        "platform" => "slack",
        "records" => [ { "id" => "C0STANDUP", "name" => "standup-bot-test", "label" => "#standup-bot-test", "is_private" => false, "is_member" => true } ],
        "success" => true,
        "message" => "Found 1 Slack channel(s).",
        "action" => nil
      },
      response.parsed_body
    )
  end

  test "creating a Slack standup stores the picked channel's ID and name" do
    sign_in(@manager, "manager-access-token")

    post api_standups_path, params: {
      standup: {
        name: "Picked Channel",
        platform: "slack",
        platform_channel: "C0STANDUP",
        platform_channel_name: "standup-bot-test",
        question_rows: [ "What changed?" ],
        schedule_type: "weekly",
        schedule_days: [ "1" ],
        send_time: "09:15",
        respect_timezone: "true",
        active: "true"
      }
    }, as: :json

    assert_response :created
    standup = Standup.order(:id).last
    assert_equal "C0STANDUP", standup.platform_channel
    assert_equal "standup-bot-test", standup.platform_channel_name
    assert_equal "#standup-bot-test", standup.channel_reference
  end
end

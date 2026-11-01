require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::ScheduleExceptionsTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = "test-admin-token"
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @owned_standup.update!(schedule_type: "daily", default_hour: 9, default_minute: 0, active: true)
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "requires authentication" do
    get api_standup_schedule_exceptions_path(@owned_standup), as: :json

    assert_response :unauthorized
  end

  test "manager views upcoming occurrences, exceptions, and notes" do
    @owned_standup.standup_schedule_exceptions.create!(exception_type: "holiday", original_date: Date.new(2026, 4, 28), reason: "Company holiday")
    @owned_standup.standup_schedule_exceptions.create!(
      exception_type: "rescheduled",
      original_date: Date.new(2026, 4, 29),
      rescheduled_date: Date.new(2026, 4, 29),
      rescheduled_time: "14:45",
      rescheduled_timezone: "UTC"
    )
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 8, 0, 0)) do
      get api_standup_schedule_exceptions_path(@owned_standup, preview_timezone: "UTC"), as: :json
    end

    assert_response :success
    body = response.parsed_body
    assert_equal "UTC", body["preview_timezone"]
    assert_equal "UTC", body["default_exception_timezone"]
    assert_includes body["time_zone_options"], "Eastern Time (US & Canada)"
    assert_equal [ "skipped_date", "holiday" ], body["exception_type_options"].map { |option| option["value"] }
    assert_equal @owned_standup.name, body.dig("standup", "name")
    assert body.dig("standup", "active")
    assert_equal "Every day at 9:00 AM", body.dig("standup", "schedule_summary")
    assert_includes body["notes"].join(" "), "Skipped, holiday, and canceled dates do not create prompts, reminders, or expected report rows"
    assert_includes body["notes"].join(" "), "responses and reports stay attached to the original standup date"

    upcoming = body["upcoming_occurrences"]
    assert_equal 8, upcoming.size
    first = upcoming.first
    assert_equal "2026-04-27", first["standup_date"]
    assert_equal "Monday, April 27, 2026 at 9:00 AM UTC", first["local_label"]
    assert_equal "Scheduled", first["status_label"]
    assert_equal "success", first["status_tone"]
    assert first["can_skip"]
    assert_nil first["note"]

    holiday = upcoming.find { |occurrence| occurrence["standup_date"] == "2026-04-28" }
    assert holiday["blocked"]
    assert_equal "warning", holiday["status_tone"]
    assert_equal "Company holiday", holiday["note"]
    assert_not holiday["can_skip"]

    moved = upcoming.find { |occurrence| occurrence["standup_date"] == "2026-04-29" }
    assert_equal "info", moved["status_tone"]
    assert_equal "Wednesday, April 29, 2026 at 2:45 PM UTC", moved["local_label"]

    assert_equal "2026-04-27", body.dig("next_occurrence", "standup_date")
    assert_equal "09:00", body.dig("next_occurrence", "local_time")
    assert_equal "2026-04-27", body.dig("next_occurrence", "local_date")

    exceptions = body["schedule_exceptions"]
    assert_equal [ "2026-04-28", "2026-04-29" ], exceptions.map { |exception| exception["original_date"] }
    assert_equal "Holiday", exceptions.first["label"]
    assert_equal "April 28, 2026", exceptions.first["original_date_label"]
    assert_nil exceptions.first["scheduled_at_label"]
    assert_equal "14:45", exceptions.last["rescheduled_time"]
    assert_equal "Wed, Apr 29 at 2:45 PM UTC", exceptions.last["scheduled_at_label"]
  end

  test "preview timezone shifts local times and falls back to UTC when invalid" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 8, 0, 0)) do
      get api_standup_schedule_exceptions_path(@owned_standup, preview_timezone: "America/New_York"), as: :json
      assert_equal "America/New_York", response.parsed_body["preview_timezone"]
      assert_match(/at 9:00 AM EDT\z/, response.parsed_body["upcoming_occurrences"].first["local_label"])

      get api_standup_schedule_exceptions_path(@owned_standup, preview_timezone: "Not/AZone"), as: :json
      assert_equal "UTC", response.parsed_body["preview_timezone"]
    end
  end

  test "manager creates skipped and holiday exceptions with audit logs" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.skip').count", 1 do
        post api_standup_schedule_exceptions_path(@owned_standup),
          params: { schedule_exception: { exception_type: "skipped_date", original_date: "2026-04-27", reason: "Team offsite" } },
          as: :json
      end
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "Skipped date saved for April 27, 2026.", body["notice"]
    assert_equal "Team offsite", body.dig("schedule_exception", "reason")
    assert_equal "skipped_date", body.dig("schedule_exception", "exception_type")
    schedule_exception = @owned_standup.standup_schedule_exceptions.find_by!(original_date: Date.new(2026, 4, 27))
    assert_equal "Team offsite", schedule_exception.reason
    assert_equal @manager, AuditLog.order(:created_at).last.actor

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.holiday').count", 1 do
        post api_standup_schedule_exceptions_path(@owned_standup),
          params: { schedule_exception: { exception_type: "holiday", original_date: "2026-04-28", reason: "Company holiday" } },
          as: :json
      end
    end
  end

  test "manager reschedules and cancels one-off occurrences with specific audit actions" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.reschedule').count", 1 do
        post api_standup_schedule_exceptions_path(@owned_standup),
          params: {
            schedule_exception: {
              exception_type: "rescheduled",
              original_date: "2026-04-29",
              rescheduled_date: "2026-04-29",
              rescheduled_time: "14:45",
              rescheduled_timezone: "UTC",
              reason: "Late team meeting"
            }
          },
          as: :json
      end
    end

    assert_response :created
    rescheduled = @owned_standup.standup_schedule_exceptions.find_by!(original_date: Date.new(2026, 4, 29))
    assert_equal Time.zone.local(2026, 4, 29, 14, 45), rescheduled.scheduled_at
    assert_equal "2026-04-29T14:45:00Z", response.parsed_body.dig("schedule_exception", "scheduled_at")

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.cancel').count", 1 do
        post api_standup_schedule_exceptions_path(@owned_standup),
          params: { schedule_exception: { exception_type: "cancelled", original_date: "2026-04-30", reason: "One-off cancellation" } },
          as: :json
      end
    end
  end

  test "rescheduling defaults the timezone to UTC" do
    sign_in(@manager, "manager-access-token")

    post api_standup_schedule_exceptions_path(@owned_standup),
      params: { schedule_exception: { exception_type: "rescheduled", original_date: "2026-04-29", rescheduled_date: "2026-04-30", rescheduled_time: "08:15" } },
      as: :json

    assert_response :created
    assert_equal "UTC", response.parsed_body.dig("schedule_exception", "rescheduled_timezone")
  end

  test "invalid reschedule returns field errors without audit log" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupScheduleException.count", "AuditLog.count" ] do
      post api_standup_schedule_exceptions_path(@owned_standup),
        params: {
          schedule_exception: {
            exception_type: "rescheduled",
            original_date: "2026-04-27",
            rescheduled_time: "25:99",
            rescheduled_timezone: "Invalid/Zone"
          }
        },
        as: :json
    end

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_includes body["errors"], "Rescheduled date can't be blank"
    assert_includes body["errors"], "Rescheduled time is not valid"
    assert_includes body["errors"], "Rescheduled timezone is not valid"
    assert_equal [ "is not valid" ], body.dig("field_errors", "rescheduled_timezone")
  end

  test "dates off the schedule are rejected" do
    @owned_standup.update!(schedule_type: "weekly", schedule_days: [ 1 ])
    sign_in(@manager, "manager-access-token")

    post api_standup_schedule_exceptions_path(@owned_standup),
      params: { schedule_exception: { exception_type: "holiday", original_date: "2026-04-28" } },
      as: :json

    assert_response :unprocessable_entity
    assert_equal [ "must be a scheduled date for this standup" ], response.parsed_body.dig("field_errors", "original_date")
  end

  test "manager removes exception with audit log" do
    sign_in(@manager, "manager-access-token")
    schedule_exception = @owned_standup.standup_schedule_exceptions.create!(exception_type: "holiday", original_date: Date.new(2026, 5, 1), reason: "Holiday")

    assert_difference "StandupScheduleException.count", -1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.remove').count", 1 do
        delete api_standup_schedule_exception_path(@owned_standup, schedule_exception), as: :json
      end
    end

    assert_response :success
    assert_equal "Removed the holiday exception for May 01, 2026.", response.parsed_body["notice"]
    assert_equal schedule_exception.id, response.parsed_body.dig("schedule_exception", "id")
    assert_equal "2026-05-01", AuditLog.where(action: "standup.schedule_exception.remove").last.metadata.dig("schedule_exception", "original_date")
  end

  test "can't remove another standup's exception" do
    schedule_exception = @unowned_standup.standup_schedule_exceptions.create!(exception_type: "holiday", original_date: Date.new(2026, 5, 4))
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupScheduleException.count" do
      delete api_standup_schedule_exception_path(@owned_standup, schedule_exception), as: :json
    end

    assert_response :not_found
  end

  test "manager cannot view or manage unowned standup exceptions" do
    sign_in(@manager, "manager-access-token")

    get api_standup_schedule_exceptions_path(@unowned_standup), as: :json
    assert_response :forbidden

    assert_no_difference [ "StandupScheduleException.count", "AuditLog.count" ] do
      post api_standup_schedule_exceptions_path(@unowned_standup),
        params: { schedule_exception: { exception_type: "holiday", original_date: "2026-05-04" } },
        as: :json
    end
    assert_response :forbidden
  end

  test "admin can manage unowned standup exceptions" do
    sign_in(@admin, "admin-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      post api_standup_schedule_exceptions_path(@unowned_standup),
        params: { schedule_exception: { exception_type: "holiday", original_date: "2026-05-04" } },
        as: :json
    end

    assert_response :created
    assert_equal @admin, AuditLog.order(:created_at).last.actor
  end

  test "the token manages exceptions with an admin_api audit" do
    get api_standup_schedule_exceptions_path(@unowned_standup), headers: token_headers, as: :json
    assert_response :success

    post api_standup_schedule_exceptions_path(@unowned_standup),
      params: { schedule_exception: { exception_type: "holiday", original_date: "2026-05-04" } },
      headers: token_headers,
      as: :json

    assert_response :created
    audit_log = AuditLog.where(action: "standup.schedule_exception.holiday").last
    assert_equal "admin_api", audit_log.actor_label
  end

  test "Teams standups use the same schedule exceptions" do
    enable_teams!
    standup = create_teams_standup!
    standup.update!(schedule_type: "daily", default_hour: 9, default_minute: 0)
    standup.standup_ownerships.create!(user: @manager)
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 8, 0, 0)) do
      get api_standup_schedule_exceptions_path(standup), as: :json
      assert_response :success
      assert_equal "teams", response.parsed_body.dig("standup", "platform")

      post api_standup_schedule_exceptions_path(standup),
        params: { schedule_exception: { exception_type: "skipped_date", original_date: "2026-04-27" } },
        as: :json
      assert_response :created
    end
  end

  private

  def token_headers
    { "Authorization" => "Bearer test-admin-token" }
  end

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :success
  end
end

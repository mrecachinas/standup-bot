require "test_helper"

class Manager::StandupScheduleExceptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @owned_standup.update!(schedule_type: "daily", default_hour: 9, default_minute: 0, active: true)
  end

  test "requires authentication" do
    get manager_standup_schedule_exceptions_path(@owned_standup)

    assert_redirected_to new_session_path
  end

  test "manager views upcoming occurrences explanatory copy and pause integration" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 8, 0, 0)) do
      get manager_standup_schedule_exceptions_path(@owned_standup, preview_timezone: "UTC")
    end

    assert_response :success
    assert_includes response.body, "Schedule exceptions"
    assert_includes response.body, "Monday, April 27, 2026 at 9:00 AM UTC"
    assert_includes response.body, "Skipped, holiday, and canceled dates do not create prompts, reminders, or expected report rows"
    assert_includes response.body, "responses and reports stay attached to the original standup date"
    assert_includes response.body, "Pause standup"
  end

  test "manager creates skipped and holiday exceptions with audit logs" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.skip').count", 1 do
        post manager_standup_schedule_exceptions_path(@owned_standup),
          params: {
            schedule_exception: {
              exception_type: "skipped_date",
              original_date: "2026-04-27",
              reason: "Team offsite"
            }
          }
      end
    end

    assert_redirected_to manager_standup_schedule_exceptions_path(@owned_standup)
    schedule_exception = @owned_standup.standup_schedule_exceptions.find_by!(original_date: Date.new(2026, 4, 27))
    assert_equal "Team offsite", schedule_exception.reason
    assert_equal @manager, AuditLog.order(:created_at).last.actor

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.holiday').count", 1 do
        post manager_standup_schedule_exceptions_path(@owned_standup),
          params: {
            schedule_exception: {
              exception_type: "holiday",
              original_date: "2026-04-28",
              reason: "Company holiday"
            }
          }
      end
    end
  end

  test "manager reschedules and cancels one-off occurrences with specific audit actions" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.reschedule').count", 1 do
        post manager_standup_schedule_exceptions_path(@owned_standup),
          params: {
            schedule_exception: {
              exception_type: "rescheduled",
              original_date: "2026-04-29",
              rescheduled_date: "2026-04-29",
              rescheduled_time: "14:45",
              rescheduled_timezone: "UTC",
              reason: "Late team meeting"
            }
          }
      end
    end

    rescheduled = @owned_standup.standup_schedule_exceptions.find_by!(original_date: Date.new(2026, 4, 29))
    assert_equal Time.zone.local(2026, 4, 29, 14, 45), rescheduled.scheduled_at

    assert_difference "StandupScheduleException.count", 1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.cancel').count", 1 do
        post manager_standup_schedule_exceptions_path(@owned_standup),
          params: {
            schedule_exception: {
              exception_type: "cancelled",
              original_date: "2026-04-30",
              reason: "One-off cancellation"
            }
          }
      end
    end
  end

  test "invalid reschedule rerenders explicit validation errors without audit log" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupScheduleException.count", "AuditLog.count" ] do
      post manager_standup_schedule_exceptions_path(@owned_standup),
        params: {
          schedule_exception: {
            exception_type: "rescheduled",
            original_date: "2026-04-27",
            rescheduled_time: "25:99",
            rescheduled_timezone: "Invalid/Zone"
          }
        }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Rescheduled date can&#39;t be blank"
    assert_includes response.body, "Rescheduled time is not valid"
    assert_includes response.body, "Rescheduled timezone is not valid"
  end

  test "manager removes exception with audit log" do
    sign_in(@manager, "manager-access-token")
    schedule_exception = @owned_standup.standup_schedule_exceptions.create!(
      exception_type: "holiday",
      original_date: Date.new(2026, 5, 1),
      reason: "Holiday"
    )

    assert_difference "StandupScheduleException.count", -1 do
      assert_difference "AuditLog.where(action: 'standup.schedule_exception.remove').count", 1 do
        delete manager_standup_schedule_exception_path(@owned_standup, schedule_exception)
      end
    end

    assert_redirected_to manager_standup_schedule_exceptions_path(@owned_standup)
  end

  test "manager cannot view or manage unowned standup exceptions" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_schedule_exceptions_path(@unowned_standup)
    assert_response :forbidden

    assert_no_difference [ "StandupScheduleException.count", "AuditLog.count" ] do
      post manager_standup_schedule_exceptions_path(@unowned_standup),
        params: {
          schedule_exception: {
            exception_type: "holiday",
            original_date: "2026-05-04"
          }
        }
    end
    assert_response :forbidden
  end

  test "admin can manage unowned standup exceptions" do
    sign_in(@admin, "admin-access-token")

    assert_difference "StandupScheduleException.count", 1 do
      post manager_standup_schedule_exceptions_path(@unowned_standup),
        params: {
          schedule_exception: {
            exception_type: "holiday",
            original_date: "2026-05-04"
          }
        }
    end

    assert_redirected_to manager_standup_schedule_exceptions_path(@unowned_standup)
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

require "test_helper"

class StandupScheduleExceptionTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
    @standup.update!(schedule_type: "daily", default_hour: 9, default_minute: 0)
  end

  test "validates reschedule details explicitly" do
    schedule_exception = @standup.standup_schedule_exceptions.new(
      exception_type: "rescheduled",
      original_date: Date.new(2026, 4, 27),
      rescheduled_date: nil,
      rescheduled_time: "25:99",
      rescheduled_timezone: "Invalid/Zone"
    )

    assert_not schedule_exception.valid?
    assert_includes schedule_exception.errors[:rescheduled_date], "can't be blank"
    assert_includes schedule_exception.errors[:rescheduled_time], "is not valid"
    assert_includes schedule_exception.errors[:rescheduled_timezone], "is not valid"
  end

  test "requires exception dates to match the base schedule" do
    @standup.update!(schedule_type: "weekly", schedule_days: [ 1 ])

    schedule_exception = @standup.standup_schedule_exceptions.new(
      exception_type: "holiday",
      original_date: Date.new(2026, 4, 28)
    )

    assert_not schedule_exception.valid?
    assert_includes schedule_exception.errors[:original_date], "must be a scheduled date for this standup"
  end

  test "upcoming occurrences include blocked exceptions and skip them for sendable preview" do
    Timecop.freeze(Time.zone.local(2026, 4, 27, 8, 0, 0)) do
      skipped = @standup.standup_schedule_exceptions.create!(
        exception_type: "skipped_date",
        original_date: Date.new(2026, 4, 27),
        reason: "Team offsite"
      )
      holiday = @standup.standup_schedule_exceptions.create!(
        exception_type: "holiday",
        original_date: Date.new(2026, 4, 28),
        reason: "Company holiday"
      )
      rescheduled = @standup.standup_schedule_exceptions.create!(
        exception_type: "rescheduled",
        original_date: Date.new(2026, 4, 29),
        rescheduled_date: Date.new(2026, 4, 29),
        rescheduled_time: "15:30",
        rescheduled_timezone: "UTC"
      )

      occurrences = @standup.upcoming_occurrence_details_in_timezone("UTC", count: 4, include_blocked: true)

      assert_equal [ skipped, holiday, rescheduled ], occurrences.first(3).map(&:exception)
      assert_equal [ "skipped", "holiday", "rescheduled", "scheduled" ], occurrences.map(&:status)
      assert_equal Time.zone.local(2026, 4, 29, 15, 30), occurrences.third.scheduled_at

      sendable_times = @standup.upcoming_occurrences_in_timezone("UTC", count: 3)
      assert_equal [
        Time.zone.local(2026, 4, 29, 15, 30),
        Time.zone.local(2026, 4, 30, 9, 0),
        Time.zone.local(2026, 5, 1, 9, 0)
      ], sendable_times
    end
  end

  test "blocking exceptions change expected schedule while reschedules remain expected on original date" do
    skip_date = Date.new(2026, 4, 27)
    rescheduled_date = Date.new(2026, 4, 28)

    @standup.standup_schedule_exceptions.create!(exception_type: "cancelled", original_date: skip_date)
    @standup.standup_schedule_exceptions.create!(
      exception_type: "rescheduled",
      original_date: rescheduled_date,
      rescheduled_date: rescheduled_date,
      rescheduled_time: "11:00",
      rescheduled_timezone: "UTC"
    )

    assert_not @standup.scheduled_on_date?(skip_date)
    assert @standup.scheduled_on_date?(rescheduled_date)
    assert @standup.scheduled_without_exceptions_on_date?(skip_date)
  end
end

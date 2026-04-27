require "test_helper"
require "timecop"

class StandupTest < ActiveSupport::TestCase
  def setup
    @daily_standup = standups(:daily)
    @weekdays_standup = standups(:weekdays)
    @weekly_standup = standups(:weekly)
  end

  test "should be valid with required attributes" do
    standup = Standup.new(
      name: "Test Standup",
      slack_channel: "test-channel",
      questions: [ "How are you?" ],
      schedule_type: "daily",
      respect_timezone: true,
      default_hour: 9,
      default_minute: 0,
      active: true
    )
    assert standup.valid?
  end

  test "should not be valid without name" do
    @daily_standup.name = nil
    assert_not @daily_standup.valid?
    assert_includes @daily_standup.errors[:name], "can't be blank"
  end

  test "should not be valid without slack_channel" do
    @daily_standup.slack_channel = nil
    assert_not @daily_standup.valid?
    assert_includes @daily_standup.errors[:slack_channel], "can't be blank"
  end

  test "should not be valid without questions" do
    @daily_standup.questions = nil
    assert_not @daily_standup.valid?
    assert_includes @daily_standup.errors[:questions], "can't be blank"
  end

  test "should not be valid with invalid schedule_type" do
    Timecop.freeze(Time.new(2025, 4, 6)) do
      @daily_standup.schedule_type = "invalid"
      assert_not @daily_standup.valid?
      assert_includes @daily_standup.errors[:schedule_type], "is not included in the list"
    end
  end

  test "should calculate next occurrence for daily standup" do
    # Use Timecop to freeze time at 8am UTC
    Timecop.freeze(Time.new(2025, 4, 6, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]

      # Daily standup at 9:00
      @daily_standup.default_hour = 9
      @daily_standup.default_minute = 0

      expected_time = Time.new(2025, 4, 6, 9, 0, 0, "+00:00")
      assert_equal expected_time, @daily_standup.next_occurrence_in_timezone(timezone)
    end

    # Use Timecop to freeze time at 10am (after scheduled time)
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]

      @daily_standup.default_hour = 9
      @daily_standup.default_minute = 0

      expected_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")
      assert_equal expected_time, @daily_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should calculate next occurrence for weekdays standup" do
    # Use Timecop to freeze time on Friday after scheduled time
    Timecop.freeze(Time.new(2025, 4, 4, 10, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]

      @weekdays_standup.default_hour = 9
      @weekdays_standup.default_minute = 0

      # Since it's after scheduled time on Friday, next occurrence should be Monday
      expected_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekdays_standup.next_occurrence_in_timezone(timezone)
    end

    # Use Timecop to freeze time on Saturday
    Timecop.freeze(Time.new(2025, 4, 5, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]

      @weekdays_standup.default_hour = 9
      @weekdays_standup.default_minute = 0

      expected_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekdays_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should calculate next occurrence for weekly standup" do
    # Use Timecop to freeze time on Sunday
    Timecop.freeze(Time.new(2025, 4, 6, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]

      @weekly_standup.default_hour = 9
      @weekly_standup.default_minute = 0
      @weekly_standup.schedule_days = [ 1 ] # Monday

      # Next occurrence should be Monday, April 7th
      expected_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekly_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should calculate next occurrence for biweekly standup" do
    Timecop.freeze(Time.new(2024, 1, 8, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]
      @weekly_standup.update!(schedule_type: "biweekly", schedule_days: [ 1 ], default_hour: 9, default_minute: 0)

      expected_time = Time.new(2024, 1, 15, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekly_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should calculate next occurrence for monthly standup using month end when needed" do
    Timecop.freeze(Time.new(2025, 2, 15, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]
      @weekly_standup.update!(schedule_type: "monthly", schedule_days: [ 31 ], default_hour: 9, default_minute: 0)

      expected_time = Time.new(2025, 2, 28, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekly_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should calculate next occurrence for custom weekday schedules" do
    Timecop.freeze(Time.new(2025, 4, 6, 8, 0, 0, "+00:00")) do
      timezone = ActiveSupport::TimeZone["UTC"]
      @weekly_standup.update!(schedule_type: "custom", schedule_days: [ 2, 4 ], default_hour: 9, default_minute: 0)

      expected_time = Time.new(2025, 4, 8, 9, 0, 0, "+00:00")
      assert_equal expected_time, @weekly_standup.next_occurrence_in_timezone(timezone)
    end
  end

  test "should validate schedule day ranges" do
    @weekly_standup.schedule_type = "custom"
    @weekly_standup.schedule_days = [ 7 ]

    assert_not @weekly_standup.valid?
    assert_includes @weekly_standup.errors[:schedule_days], "contains invalid days for custom schedule"
  end

  test "should require custom schedule days" do
    @weekly_standup.schedule_type = "custom"
    @weekly_standup.schedule_days = []

    assert_not @weekly_standup.valid?
    assert_includes @weekly_standup.errors[:schedule_days], "must include at least one weekday for custom schedule"
  end

  test "normalizes and validates Slack channel input" do
    standup = Standup.new(
      name: "Channel Validation",
      slack_channel: " #team-standup ",
      questions: [ "Question?" ],
      schedule_type: "daily",
      respect_timezone: true
    )

    assert standup.valid?
    assert_equal "team-standup", standup.slack_channel

    standup.slack_channel = "bad channel"
    assert_not standup.valid?
    assert_includes standup.errors[:slack_channel], "must be a Slack channel name or ID without spaces"
  end

  test "normalizes blank questions before validation" do
    @daily_standup.questions = [ "  Keep me  ", "", "   " ]

    assert @daily_standup.valid?
    assert_equal [ "Keep me" ], @daily_standup.questions
  end

  test "previews upcoming occurrences without persisting" do
    Timecop.freeze(Time.new(2025, 4, 6, 8, 0, 0, "+00:00")) do
      @weekly_standup.assign_attributes(schedule_type: "custom", schedule_days: [ 1, 3 ], default_hour: 9, default_minute: 30)

      occurrences = @weekly_standup.upcoming_occurrences_in_timezone("UTC", count: 3)

      assert_equal [
        Time.new(2025, 4, 7, 9, 30, 0, "+00:00"),
        Time.new(2025, 4, 9, 9, 30, 0, "+00:00"),
        Time.new(2025, 4, 14, 9, 30, 0, "+00:00")
      ], occurrences
    end
  end
end

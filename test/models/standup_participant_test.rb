require "test_helper"
require "timecop"

class StandupParticipantTest < ActiveSupport::TestCase
  def setup
    @standup = standups(:daily)
    @participant = standup_participants(:one)
  end

  test "should be valid with required attributes" do
    Timecop.freeze(Time.new(2025, 4, 6)) do
      participant = StandupParticipant.new(
        standup: @standup,
        slack_id: "U123NEW",
        active: true
      )
      assert participant.valid?
    end
  end

  test "should not be valid without slack_id" do
    Timecop.freeze(Time.new(2025, 4, 6)) do
      @participant.slack_id = nil
      assert_not @participant.valid?
      assert_includes @participant.errors[:slack_id], "can't be blank"
    end
  end

  test "should not allow duplicate slack_id in same standup" do
    Timecop.freeze(Time.new(2025, 4, 6)) do
      duplicate = StandupParticipant.new(
        standup: @participant.standup,
        slack_id: @participant.slack_id
      )
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:slack_id], "has already been taken"
    end
  end

  test "should allow same slack_id in different standups" do
    Timecop.freeze(Time.new(2025, 4, 6)) do
      different_standup = standups(:weekly)
      participant = StandupParticipant.new(
        standup: different_standup,
        slack_id: @participant.slack_id
      )
      assert participant.valid?
    end
  end

  test "should fetch info from Slack" do
    slack_client_mock = mock()
    user_info = { "tz" => "America/New_York" }
    slack_client_mock.expects(:get_user_info).with(@participant.slack_id).returns(user_info)

    SlackClient.expects(:new).returns(slack_client_mock)

    assert_equal user_info, @participant.fetch_info
  end

  test "should get timezone from Slack info" do
    @participant.expects(:fetch_info).returns({ "tz" => "America/Los_Angeles" })
    assert_equal "America/Los_Angeles", @participant.timezone

    # Clear cached timezone to test fallback behavior
    @participant.update_column(:cached_timezone, nil)

    # Test fallback to UTC when timezone info unavailable
    @participant.expects(:fetch_info).returns(nil)
    assert_equal "UTC", @participant.timezone
  end

  test "should calculate send time based on participant timezone when respecting timezone" do
    @standup.update(respect_timezone: true)
    timezone_name = "America/New_York"

    # Fix the time to a known point
    Timecop.freeze(Time.new(2025, 4, 7, 5, 0, 0)) do
      # Mock only the timezone lookup part
      @participant.expects(:timezone).returns(timezone_name)

      # Define standup schedule (assuming 9am in the participant's timezone)
      @standup.update(default_hour: 9, default_minute: 0)

      # Expected UTC time (9am ET = 13:00 UTC on April 7, 2025)
      expected_utc_time = Time.new(2025, 4, 7, 13, 0, 0, "+00:00")

      # The actual calculation
      result = @participant.calculate_send_time

      assert_equal expected_utc_time.utc.to_i, result.utc.to_i
    end
  end

  test "should calculate send time using UTC when not respecting timezone" do
    # Use Timecop to freeze time for deterministic testing
    Timecop.freeze(Time.new(2025, 4, 7, 5, 0, 0)) do
      @standup.update(respect_timezone: false)
      @standup.update(default_hour: 9, default_minute: 0)

      # When not respecting timezone, we expect 9:00 UTC regardless of participant timezone
      expected_utc_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")

      # Should not try to get participant timezone
      @participant.expects(:timezone).never

      result = @participant.calculate_send_time
      assert_equal expected_utc_time.utc.to_i, result.utc.to_i
    end
  end
end

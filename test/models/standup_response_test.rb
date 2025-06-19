require "test_helper"
require "timecop"

class StandupResponseTest < ActiveSupport::TestCase
  def setup
    @standup = standups(:daily)
    @response = standup_responses(:one)
  end

  test "should be valid with required attributes" do
    response = StandupResponse.new(
      standup: @standup,
      slack_id: "U123NEW",
      status: "pending",
      answers: []
    )
    assert response.valid?
  end

  test "should not be valid without slack_id" do
    @response.slack_id = nil
    assert_not @response.valid?
    assert_includes @response.errors[:slack_id], "can't be blank"
  end

  test "should not be valid with invalid status" do
    @response.status = "invalid"
    assert_not @response.valid?
    assert_includes @response.errors[:status], "is not included in the list"
  end

  test "should be valid with any valid status" do
    valid_statuses = %w[pending completed skipped]

    valid_statuses.each do |status|
      @response.status = status
      assert @response.valid?, "Status #{status} should be valid"
    end
  end

  test "pending scope should return only pending responses" do
    pending_response = standup_responses(:pending)
    completed_response = standup_responses(:completed)

    assert_includes StandupResponse.pending, pending_response
    assert_not_includes StandupResponse.pending, completed_response
  end

  test "completed scope should return only completed responses" do
    pending_response = standup_responses(:pending)
    completed_response = standup_responses(:completed)

    assert_includes StandupResponse.completed, completed_response
    assert_not_includes StandupResponse.completed, pending_response
  end

  test "skipped scope should return only skipped responses" do
    # Create a skipped response
    skipped_response = StandupResponse.create!(
      standup: @response.standup,
      slack_id: "U99999",
      status: "skipped",
      answers: []
    )

    pending_response = standup_responses(:pending)
    completed_response = standup_responses(:completed)

    assert_includes StandupResponse.skipped, skipped_response
    assert_not_includes StandupResponse.skipped, pending_response
    assert_not_includes StandupResponse.skipped, completed_response
  end

  test "for_today scope should return only responses created today" do
    today_response = standup_responses(:today)
    yesterday_response = standup_responses(:yesterday)

    # Use Timecop to freeze time at a specific time in UTC
    Timecop.freeze(Time.new(2025, 4, 6, 12, 0, 0, "+00:00")) do
      assert_includes StandupResponse.for_today, today_response
      assert_not_includes StandupResponse.for_today, yesterday_response
    end
  end

  test "should find participant by slack_id" do
    participant = standup_participants(:one)
    @response.slack_id = participant.slack_id
    @response.standup = participant.standup

    assert_equal participant, @response.participant
  end

  test "should store and retrieve answers as array" do
    # Use Timecop to ensure consistent timestamps in test
    Timecop.freeze(Time.new(2025, 4, 6, 12, 0, 0)) do
      answers = [
        { "question" => "What did you do yesterday?", "answer" => "Coding", "timestamp" => Time.now.iso8601 },
        { "question" => "What will you do today?", "answer" => "More coding", "timestamp" => (Time.now + 1.minute).iso8601 }
      ]

      @response.answers = answers
      @response.save!

      # Reload from database to ensure serialization works
      reloaded_response = StandupResponse.find(@response.id)

      assert_equal answers, reloaded_response.answers
      assert_equal "More coding", reloaded_response.answers.last["answer"]
    end
  end
end

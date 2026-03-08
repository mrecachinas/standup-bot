require "test_helper"
require "timecop"

class NonResponseHandlingTest < ActiveSupport::TestCase
  setup do
    # Create a test standup
    @standup = Standup.create!(
      name: "Daily Integration Test",
      slack_channel: "general",
      questions: [ "What did you work on yesterday?", "What are you working on today?" ],
      intro: "Time for standup!",
      outro: "Thanks!"
    )

    @slack_id = "U12345"

    # Mock the slack client
    @mock_slack_client = mock("SlackClient")
    StandupMessageJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)
  end

  test "user gets new standup after not completing previous one" do
    # Simulate the scenario over multiple days
    Timecop.freeze(Time.new(2025, 4, 6, 9, 0, 0, "+00:00")) do
      # Day 1: User gets standup but doesn't complete it
      @mock_slack_client.expects(:send_message)
        .with(@slack_id, is_a(String))
        .returns({ channel: "D12345", ts: "1234567890.123456" })
        .once

      # Schedule standup for day 1
      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify pending response was created
      day1_response = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).last
      assert_equal "pending", day1_response.status
      assert_empty day1_response.answers
      assert_equal 1, StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).count
    end

    # Move to Day 2
    Timecop.freeze(Time.new(2025, 4, 7, 9, 0, 0, "+00:00")) do
      # Day 2: User gets a new standup
      @mock_slack_client.expects(:send_message)
        .with(@slack_id, is_a(String))
        .returns({ channel: "D12345", ts: "1234567890.123457" })
        .once

      # Schedule standup for day 2
      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify that we now have 2 responses
      responses = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).order(:created_at)
      assert_equal 2, responses.count

      # Verify that day 1 response was canceled
      day1_response = responses.first
      assert_equal "skipped", day1_response.status

      # Verify that day 2 response is pending
      day2_response = responses.last
      assert_equal "pending", day2_response.status
      assert_empty day2_response.answers
    end

    # Move to Day 3
    Timecop.freeze(Time.new(2025, 4, 8, 9, 0, 0, "+00:00")) do
      # Day 3: User gets another new standup
      @mock_slack_client.expects(:send_message)
        .with(@slack_id, is_a(String))
        .returns({ channel: "D12345", ts: "1234567890.123458" })
        .once

      # Schedule standup for day 3
      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify that we now have 3 responses
      responses = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).order(:created_at)
      assert_equal 3, responses.count

      # Verify that both day 1 and day 2 responses were canceled
      assert_equal "skipped", responses[0].status  # Day 1
      assert_equal "skipped", responses[1].status  # Day 2
      assert_equal "pending", responses[2].status  # Day 3
    end
  end

  test "user responses are preserved within the same day" do
    Timecop.freeze(Time.new(2025, 4, 6, 9, 0, 0, "+00:00")) do
      # Morning: User gets standup
      @mock_slack_client.expects(:send_message)
        .with(@slack_id, is_a(String))
        .returns({ channel: "D12345", ts: "1234567890.123456" })
        .once

      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify pending response was created
      morning_response = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).last
      assert_equal "pending", morning_response.status

      # Later in the day: Another standup message is triggered but should be skipped
      # because a pending response already exists for today
      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify that only 1 response exists (dedup prevents second)
      responses = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).order(:created_at)
      assert_equal 1, responses.count
      assert_equal "pending", responses[0].status  # Morning response should still be pending
    end
  end

  test "completed responses are never canceled" do
    Timecop.freeze(Time.new(2025, 4, 6, 9, 0, 0, "+00:00")) do
      # Day 1: User gets standup and completes it
      completed_response = StandupResponse.create!(
        slack_id: @slack_id,
        standup_id: @standup.id,
        status: "completed",
        answers: [
          { "question" => "What did you work on yesterday?", "answer" => "Feature X", "timestamp" => Time.current },
          { "question" => "What are you working on today?", "answer" => "Feature Y", "timestamp" => Time.current }
        ]
      )
    end

    # Move to Day 2
    Timecop.freeze(Time.new(2025, 4, 7, 9, 0, 0, "+00:00")) do
      # Day 2: User gets a new standup
      @mock_slack_client.expects(:send_message)
        .with(@slack_id, is_a(String))
        .returns({ channel: "D12345", ts: "1234567890.123457" })
        .once

      StandupMessageJob.perform_now(@slack_id, @standup.id)

      # Verify that we have 2 responses
      responses = StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).order(:created_at)
      assert_equal 2, responses.count

      # Verify that day 1 completed response was NOT canceled
      day1_response = responses.first
      assert_equal "completed", day1_response.status

      # Verify that day 2 response is pending
      day2_response = responses.last
      assert_equal "pending", day2_response.status
    end
  end
end

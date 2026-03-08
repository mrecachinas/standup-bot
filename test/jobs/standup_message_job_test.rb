require "test_helper"

class StandupMessageJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @slack_id = "U12345"

    # Mock the slack client
    @mock_slack_client = mock("SlackClient")
    StandupMessageJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)

    # Setup test data
    @standup.questions = [ "What did you do yesterday?", "What are you doing today?", "Any blockers?" ]
    @standup.intro = "Time for standup!"
    @standup.save!

    # Mock response from Slack
    @message_response = { channel: "D12345", ts: "1234567890.123456" }
  end

  test "sends standup message to slack user" do
    # Expect the message to be sent to Slack
    @mock_slack_client.expects(:send_message)
      .with(@slack_id, is_a(String))
      .returns(@message_response)

    # Verify that a standup response is created
    assert_difference "StandupResponse.count", 1 do
      StandupMessageJob.perform_now(@slack_id, @standup.id)
    end

    # Verify the created standup response
    response = StandupResponse.last
    assert_equal @slack_id, response.slack_id
    assert_equal @standup.id, response.standup_id
    assert_equal "pending", response.status
    assert_equal @message_response[:channel], response.slack_channel
    assert_empty response.answers
  end

  test "formats the message with intro and first question" do
    # Verify the message includes the intro and first question
    formatted_question = StandupFormatter.format_question(
      @standup.questions.first,
      1,
      @standup.questions.size
    )

    expected_message = [
      @standup.intro,
      "",
      formatted_question
    ].join("\n")

    @mock_slack_client.expects(:send_message)
      .with(@slack_id, expected_message)
      .returns(@message_response)

    StandupMessageJob.perform_now(@slack_id, @standup.id)
  end

  test "silently discards job when standup not found" do
    # With discard_on ActiveRecord::RecordNotFound, the job should
    # complete without raising when the standup doesn't exist
    assert_nothing_raised do
      StandupMessageJob.perform_now(@slack_id, 999999)
    end
  end

  test "handles slack client errors" do
    # Set up the expectation that send_message will be called and raise an error
    @mock_slack_client.expects(:send_message)
      .with(@slack_id, is_a(String))
      .raises(StandardError.new("Slack API Error"))
      .once  # Explicitly state we expect this to be called only once

    # Verify no standup response is created when an error occurs
    assert_no_difference "StandupResponse.count" do
      assert_raises(StandardError) do
        StandupMessageJob.perform_now(@slack_id, @standup.id)
      end
    end
  end

  test "cancels previous pending responses before creating new one" do
    # Create a previous pending response
    old_response = StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "pending",
      answers: [ { "question" => "Test", "answer" => "Test answer", "timestamp" => Time.current } ],
      created_at: 1.day.ago
    )

    # Expect the cancel method to be called
    StandupResponseService.expects(:cancel_previous_pending_responses)
      .with(@slack_id, @standup.id)
      .once

    # Expect the message to be sent to Slack
    @mock_slack_client.expects(:send_message)
      .with(@slack_id, is_a(String))
      .returns(@message_response)

    # Perform the job
    StandupMessageJob.perform_now(@slack_id, @standup.id)
  end
end

require "test_helper"

class StandupMessageJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @participant = standup_participants(:one)
    @participant.update!(
      active: true,
      vacation_until: nil,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )
    @slack_id = @participant.slack_id
    StandupResponse.where(slack_id: @slack_id, standup_id: @standup.id).delete_all

    # Mock the slack client
    @mock_slack_client = mock("SlackClient")
    StandupMessageJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)

    # Setup test data
    @standup.questions = [ "What did you do yesterday?", "What are you doing today?", "Any blockers?" ]
    @standup.intro = "Time for standup!"
    @standup.save!

    # Mock response from Slack
    @message_response = { "channel" => "D12345", "ts" => "1234567890.123456" }
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
    assert_equal @message_response["channel"], response.slack_channel
    assert_equal Time.zone.today, response.standup_date
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
    StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "pending",
      answers: [ { "question" => "Test", "answer" => "Test answer", "timestamp" => Time.current } ],
      created_at: 1.day.ago
    )

    standup_date = Date.new(2025, 4, 7)

    # Expect the cancel method to be called
    StandupResponseService.expects(:cancel_previous_pending_responses)
      .with(@slack_id, @standup.id, standup_date, @participant.standup_time_zone)
      .once

    # Expect the message to be sent to Slack
    @mock_slack_client.expects(:send_message)
      .with(@slack_id, is_a(String))
      .returns(@message_response)

    # Perform the job
    StandupMessageJob.perform_now(@slack_id, @standup.id, standup_date.iso8601)
  end

  test "does not send duplicate standup for same standup date" do
    StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "pending",
      standup_date: Date.new(2025, 4, 7),
      answers: []
    )

    @mock_slack_client.expects(:send_message).never

    assert_no_difference "StandupResponse.count" do
      StandupMessageJob.perform_now(@slack_id, @standup.id, "2025-04-07")
    end
  end

  test "does not send duplicate when existing same-day response has nil standup date" do
    Timecop.freeze(Time.zone.local(2025, 4, 7, 12, 0, 0)) do
      response = StandupResponse.create!(
        slack_id: @slack_id,
        standup_id: @standup.id,
        status: "pending",
        answers: [],
        created_at: Time.current
      )
      response.update_column(:standup_date, nil)

      @mock_slack_client.expects(:send_message).never

      assert_no_difference "StandupResponse.count" do
        StandupMessageJob.perform_now(@slack_id, @standup.id, "2025-04-07")
      end
    end
  end

  test "does not send when schedule exception cancels the standup date" do
    standup_date = Date.new(2026, 5, 1)
    @standup.standup_schedule_exceptions.create!(
      exception_type: "cancelled",
      original_date: standup_date,
      reason: "One-off cancellation"
    )

    @mock_slack_client.expects(:send_message).never

    assert_no_difference "StandupResponse.count" do
      StandupMessageJob.perform_now(@slack_id, @standup.id, standup_date.iso8601)
    end
  end
end

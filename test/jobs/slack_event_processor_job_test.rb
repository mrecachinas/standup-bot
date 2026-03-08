require "test_helper"

class SlackEventProcessorJobTest < ActiveJob::TestCase
  setup do
    @slack_commands = mock("SlackCommands")
    SlackCommands.stubs(:new).returns(@slack_commands)

    @slack_id = "U12345"
    @channel_id = "C12345"

    # Create a pending standup response for testing
    @standup = standups(:daily)
    @standup_response = StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "pending",
      answers: []
    )

    # Mock the StandupResponseService for verification
    @standup_response_service = mock("StandupResponseService")
    StandupResponseService.stubs(:record_answer).returns(true)
  end

  test "ignores non-message events" do
    event = { "type" => "reaction_added" }

    # Ensure no processing happens for non-message events
    SlackCommands.expects(:new).never

    SlackEventProcessorJob.perform_now(event)
  end

  test "processes commands" do
    event = {
      "type" => "message",
      "user" => @slack_id,
      "text" => "/standup help",
      "channel" => @channel_id
    }

    # Setup command parsing expectation
    @slack_commands.expects(:parse).with(event["text"]).returns({
      command: "standup",
      subcommand: "help",
      args: []
    })

    # Command should be processed
    @slack_commands.expects(:process).with(
      { command: "standup", subcommand: "help", args: [] },
      @slack_id,
      @channel_id
    )

    # StandupResponseService should not be called for commands
    StandupResponseService.expects(:record_answer).never

    SlackEventProcessorJob.perform_now(event)
  end

  test "processes standup responses" do
    event = {
      "type" => "message",
      "user" => @slack_id,
      "text" => "I worked on feature X",
      "channel" => @channel_id
    }

    # Setup command parsing expectation to return nil (not a command)
    @slack_commands.expects(:parse).with(event["text"]).returns(nil)

    # StandupResponseService should be called with the response
    StandupResponseService.expects(:record_answer)
      .with(@standup_response, event["text"])

    SlackEventProcessorJob.perform_now(event)
  end

  test "ignores messages if no pending standup response" do
    # Delete existing standup responses for this test
    StandupResponse.where(slack_id: @slack_id).delete_all

    event = {
      "type" => "message",
      "user" => @slack_id,
      "text" => "Hello world",
      "channel" => @channel_id
    }

    # Setup command parsing expectation to return nil (not a command)
    @slack_commands.expects(:parse).with(event["text"]).returns(nil)

    # StandupResponseService should not be called
    StandupResponseService.expects(:record_answer).never

    SlackEventProcessorJob.perform_now(event)
  end

  test "processes edited message for pending standup response" do
    # Add an initial answer to the standup response
    @standup_response.answers = [ {
      "question" => "What did you accomplish yesterday?",
      "answer" => "I worked on feature X",
      "timestamp" => Time.current
    } ]
    @standup_response.save!

    # Create a message edit event
    event = {
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => @channel_id,
      "message" => {
        "user" => @slack_id,
        "text" => "I worked on feature X and also fixed bug Y",
        "ts" => "1234567890.123456"
      },
      "previous_message" => {
        "user" => @slack_id,
        "text" => "I worked on feature X",
        "ts" => "1234567890.123456"
      }
    }

    # Perform the job
    SlackEventProcessorJob.perform_now(event)

    # Reload the response from the database
    @standup_response.reload

    # Assert that the answer was updated
    assert_equal "I worked on feature X and also fixed bug Y", @standup_response.answers.last["answer"]
  end

  test "processes edited message for completed standup response" do
    # Create a completed standup response
    completed_response = StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "completed",
      answers: [
        {
          "question" => "What did you accomplish yesterday?",
          "answer" => "I worked on feature X",
          "timestamp" => Time.current
        },
        {
          "question" => "What are you working on today?",
          "answer" => "I will work on feature Y",
          "timestamp" => Time.current
        }
      ],
      slack_message_ts: "1234567890.123456",
      created_at: Time.zone.today.beginning_of_day + 1.hour # Ensure it's from today
    )

    # Setup expectation for repost_response
    StandupResponseService.expects(:repost_response).with(completed_response)

    # Create a message edit event for the first answer
    event = {
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => @channel_id,
      "message" => {
        "user" => @slack_id,
        "text" => "I worked on feature X and also fixed bug Z",
        "ts" => "1234567890.123456"
      },
      "previous_message" => {
        "user" => @slack_id,
        "text" => "I worked on feature X",
        "ts" => "1234567890.123456"
      }
    }

    # Perform the job
    SlackEventProcessorJob.perform_now(event)

    # Reload the response from the database
    completed_response.reload

    # Assert that the answer was updated - we match it based on similarity
    assert_equal "I worked on feature X and also fixed bug Z", completed_response.answers[0]["answer"]
  end

  test "ignores edited message with no matching standup response" do
    # Delete all existing standup responses for this test
    StandupResponse.where(slack_id: @slack_id).delete_all

    # StandupResponseService should not be called
    StandupResponseService.expects(:repost_response).never

    # Create a message edit event
    event = {
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => @channel_id,
      "message" => {
        "user" => @slack_id,
        "text" => "This is an edited message with no standup response",
        "ts" => "1234567890.123456"
      },
      "previous_message" => {
        "user" => @slack_id,
        "text" => "This is a message with no standup response",
        "ts" => "1234567890.123456"
      }
    }

    # Perform the job
    SlackEventProcessorJob.perform_now(event)

    # No assertions needed, we expect no errors and the expectations above to be met
  end

  test "skips update when no specific match found in completed response" do
    # Create a completed standup response with answers that won't match the edited text
    completed_response = StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "completed",
      answers: [
        {
          "question" => "What did you accomplish yesterday?",
          "answer" => "I fixed bug A",
          "timestamp" => Time.current
        },
        {
          "question" => "What are you working on today?",
          "answer" => "I will implement feature B",
          "timestamp" => Time.current
        }
      ],
      slack_message_ts: "1234567890.123456",
      created_at: Time.zone.today.beginning_of_day + 1.hour # Ensure it's from today
    )

    # repost_response should NOT be called since no match was found
    StandupResponseService.expects(:repost_response).never

    # Create a message edit event with text that doesn't match any answer
    event = {
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => @channel_id,
      "message" => {
        "user" => @slack_id,
        "text" => "I completely forgot to mention I'm also helping with project C",
        "ts" => "1234567890.123456"
      },
      "previous_message" => {
        "user" => @slack_id,
        "text" => "Some previous text",
        "ts" => "1234567890.123456"
      }
    }

    # Perform the job
    SlackEventProcessorJob.perform_now(event)

    # Reload the response from the database
    completed_response.reload

    # Assert that answers are unchanged (no fallback corruption)
    assert_equal "I fixed bug A", completed_response.answers[0]["answer"]
    assert_equal "I will implement feature B", completed_response.answers[1]["answer"]
  end
end

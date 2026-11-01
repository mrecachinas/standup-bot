require "test_helper"

class SlackEventProcessorJobTest < ActiveJob::TestCase
  setup do
    @slack_commands = mock("SlackCommands")
    SlackCommands.stubs(:new).returns(@slack_commands)

    @slack_id = "U12345"
    @channel_id = "C12345"

    # Create a pending standup response for testing
    @standup = standups(:daily)
    @participant = standup_participants(:inactive_daily)
    @participant.update!(
      standup: @standup,
      active: true,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )
    @standup_response = StandupResponse.create!(
      slack_id: @slack_id,
      standup_id: @standup.id,
      status: "pending",
      answers: [],
      created_at: 1.day.ago,
      standup_date: 1.day.ago.to_date
    )
  end

  test "ignores non-message events" do
    event = { "type" => "reaction_added" }

    # Ensure no processing happens for non-message events
    SlackCommands.expects(:new).never

    SlackEventProcessorJob.perform_now(event)
  end

  test "routes messages to commands, pending standup answers, or ignores them" do
    command_info = { command: :help }
    @slack_commands.stubs(:parse).returns(nil)
    @slack_commands.stubs(:parse).with("help").returns(command_info)
    @slack_commands.expects(:process).with(command_info, @slack_id, @channel_id).once
    StandupResponseService.expects(:record_answer).with(@standup_response, "I worked on feature X").once

    perform_message("help")
    perform_message("I worked on feature X")

    StandupResponse.where(slack_id: @slack_id).delete_all
    perform_message("Hello world")
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
    @standup_response.destroy!

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

  test "processes edited completed response using participant timezone date" do
    @participant.update!(cached_timezone: "America/Los_Angeles", cached_timezone_updated_at: Time.current)
    @standup_response.destroy!

    Timecop.freeze(Time.new(2025, 4, 7, 6, 30, 0, "+00:00")) do
      completed_response = StandupResponse.create!(
        slack_id: @slack_id,
        standup_id: @standup.id,
        status: "completed",
        standup_date: Date.new(2025, 4, 6),
        answers: [
          {
            "question" => "What did you accomplish yesterday?",
            "answer" => "I worked on feature X",
            "timestamp" => Time.current
          }
        ],
        slack_message_ts: "1234567890.123456",
        created_at: Time.new(2025, 4, 6, 20, 0, 0, "+00:00")
      )

      StandupResponseService.expects(:repost_response).with(completed_response)

      event = {
        "type" => "message",
        "subtype" => "message_changed",
        "channel" => @channel_id,
        "message" => {
          "user" => @slack_id,
          "text" => "I worked on feature X and fixed bug Z",
          "ts" => "1234567890.123456"
        }
      }

      SlackEventProcessorJob.perform_now(event)

      assert_equal "I worked on feature X and fixed bug Z", completed_response.reload.answers[0]["answer"]
    end
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
    @standup_response.destroy!

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

  private

  def perform_message(text)
    SlackEventProcessorJob.perform_now(
      "type" => "message",
      "user" => @slack_id,
      "text" => text,
      "channel" => @channel_id
    )
  end
end

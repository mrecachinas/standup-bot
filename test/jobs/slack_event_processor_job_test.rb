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
end

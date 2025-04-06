class SlackEventProcessorJob < ApplicationJob
  queue_as :default

  def perform(event)
    Rails.logger.info "Processing Slack event: #{event['type'] || 'unknown type'}"

    return unless event["type"] == "message"

    user_id = event["user"]
    text = event["text"]
    channel = event["channel"]

    Rails.logger.info "Processing message from user: #{user_id} in channel: #{channel}"

    # Create dependencies
    slack_commands = SlackCommands.new(slack_client)

    # Check if this is a command
    command_info = slack_commands.parse(text)
    if command_info
      Rails.logger.info "Detected Slack command: #{command_info[:command]}"
      slack_commands.process(command_info, user_id, channel)
      return
    end

    # If not a command, process as a standup response
    standup_response = StandupResponse
      .where(slack_id: user_id, status: "pending")
      .order(created_at: :desc)
      .first

    if standup_response
      Rails.logger.info "Processing standup response for user #{user_id}, standup ID: #{standup_response.standup_id}"
      # Update the standup response with the user's message
      StandupResponseService.record_answer(standup_response, text)
    else
      Rails.logger.info "No pending standup response for user #{user_id}, message ignored"
    end
  end
end

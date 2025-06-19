class SlackEventProcessorJob < ApplicationJob
  queue_as :default

  def perform(event)
    Rails.logger.info "Processing Slack event: #{event['type'] || 'unknown type'}"

    # Handle message edits
    if event["type"] == "message" && event["subtype"] == "message_changed"
      return process_edited_message(event)
    end

    return unless event["type"] == "message"

    # Regular message processing
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

  private

  def process_edited_message(event)
    # Extract required information from the edit event
    user_id = event.dig("message", "user") || event["user"]
    text = event.dig("message", "text")
    channel = event["channel"]
    message_ts = event.dig("message", "ts")

    Rails.logger.info "Processing edited message from user: #{user_id} in channel: #{channel}"

    # First check for pending responses - easier case
    pending_response = StandupResponse.where(slack_id: user_id, status: "pending").order(created_at: :desc).first

    if pending_response && pending_response.answers.present?
      # Update the last answer in the pending response
      update_pending_response(pending_response, text)
      return
    end

    # Otherwise look for completed responses from today
    completed_response = StandupResponse
      .where(slack_id: user_id, status: "completed")
      .where("created_at > ?", Date.today.beginning_of_day)
      .order(created_at: :desc)
      .first

    if completed_response
      # Update the completed response and repost to channel
      update_completed_response(completed_response, text)
    else
      Rails.logger.info "No matching standup response found for edited message from user #{user_id}"
    end
  end

  def update_pending_response(standup_response, text)
    return if text.blank?

    Rails.logger.info "Updating pending standup response #{standup_response.id} with edited message"

    # Get the last answer index (most recently added)
    last_answer_index = standup_response.answers.size - 1
    return if last_answer_index < 0

    # Update the answer text
    standup_response.answers[last_answer_index]["answer"] = text
    standup_response.answers[last_answer_index]["timestamp"] = Time.current
    standup_response.save!

    Rails.logger.info "Updated answer #{last_answer_index + 1} for standup response #{standup_response.id}"
  end

  def update_completed_response(standup_response, text)
    return if text.blank?

    Rails.logger.info "Updating completed standup response #{standup_response.id} with edited message"

    # Here we don't know which answer was edited, so we'll need to determine it
    # by matching the edited text against parts of the original answers
    edited = false

    # Find the most likely answer this edit applies to
    standup_response.answers.each_with_index do |answer, index|
      # Simple approach: if the edit is similar enough to the original answer, update it
      # More sophisticated approach could use text similarity algorithms
      if text.include?(answer["answer"]) || answer["answer"].include?(text)
        standup_response.answers[index]["answer"] = text
        standup_response.answers[index]["timestamp"] = Time.current
        edited = true
        Rails.logger.info "Updated answer #{index + 1} for standup response #{standup_response.id}"
        break
      end
    end

    # If we couldn't match a specific answer, update the last one as a fallback
    if !edited && standup_response.answers.any?
      last_idx = standup_response.answers.size - 1
      standup_response.answers[last_idx]["answer"] = text
      standup_response.answers[last_idx]["timestamp"] = Time.current
      edited = true
      Rails.logger.info "Updated last answer for standup response #{standup_response.id} as fallback"
    end

    if edited
      standup_response.save!

      # Repost the updated response to the channel
      Rails.logger.info "Reposting updated standup response to channel"
      StandupResponseService.repost_response(standup_response)
    end
  end

  def slack_client
    @slack_client ||= SlackClient.instance
  end
end

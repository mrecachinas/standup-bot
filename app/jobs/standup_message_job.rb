class StandupMessageJob < ApplicationJob
  queue_as :default

  def perform(slack_id, standup_id)
    Rails.logger.info "Sending standup message to user #{slack_id} for standup #{standup_id}"

    standup = Standup.find(standup_id)
    Rails.logger.info "Found standup: #{standup.name}"

    # Format intro with the first question
    first_question = standup.questions.first
    message_text = [
      standup.intro,
      "",
      "*Question 1/#{standup.questions.size}:* #{first_question}",
      "",
      "_Type your answer or 'skip' to skip this question._"
    ].join("\n")

    # Use the inherited slack_client
    Rails.logger.info "Sending initial standup question to user #{slack_id}"
    message_response = slack_client.send_message(slack_id, message_text)
    Rails.logger.info "Message sent successfully to channel: #{message_response[:channel]}"

    # Create a pending standup response record
    standup_response = StandupResponse.create!(
      slack_id: slack_id,
      standup_id: standup_id,
      status: "pending",
      slack_channel: message_response[:channel],
      answers: []
    )
    Rails.logger.info "Created pending standup response with ID: #{standup_response.id}"
  end
end

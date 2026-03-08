class SlackUserReactivationJob < ApplicationJob
  queue_as :default

  def perform(slack_id, participant_ids = nil)
    Rails.logger.info "Starting reactivation process for Slack user: #{slack_id}"

    # Only reactivate the specific participants that were deactivated by the away command
    participants = if participant_ids.present?
      StandupParticipant.where(id: participant_ids, slack_id: slack_id, active: false)
    else
      StandupParticipant.where(slack_id: slack_id, active: false)
    end

    Rails.logger.info "Found #{participants.count} inactive standup participants for user #{slack_id}"

    # Reactivate them
    if participants.any?
      participants.update_all(active: true)
      Rails.logger.info "Successfully reactivated #{participants.count} participants for user #{slack_id}"

      # Notify the user
      Rails.logger.info "Sending reactivation notification to user #{slack_id}"
      slack_client.send_message(
        slack_id,
        "Welcome back! You've been automatically re-enabled for standups."
      )
      Rails.logger.info "Reactivation notification sent to user #{slack_id}"
    else
      Rails.logger.info "No inactive participants found for user #{slack_id}, no action needed"
    end
  end
end

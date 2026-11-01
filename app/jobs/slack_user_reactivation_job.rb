class SlackUserReactivationJob < ApplicationJob
  queue_as :default

  def perform(slack_id, participant_ids = nil)
    # Only reactivate the participants the away command deactivated, when known.
    participants = StandupParticipant.where(slack_id: slack_id, active: false)
    participants = participants.where(id: participant_ids) if participant_ids.present?
    standup = participants.includes(:standup).first&.standup

    reactivated = participants.update_all(active: true, vacation_until: nil)
    Rails.logger.info "Reactivated #{reactivated} standup participants for #{slack_id}"
    return if reactivated.zero?

    chat_for(standup).send_direct_message(slack_id, "Welcome back! You've been automatically re-enabled for standups.")
  end
end

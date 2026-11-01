class SlackUserReactivationJob < ApplicationJob
  queue_as :default

  def perform(platform_user_id, participant_ids = nil, platform = ChatPlatform::DEFAULT.to_s)
    # Only reactivate the participants the away command deactivated, when known.
    participants = StandupParticipant.on_platform(platform).where(platform_user_id: platform_user_id, active: false)
    participants = participants.where(id: participant_ids) if participant_ids.present?

    reactivated = participants.update_all(active: true, vacation_until: nil)
    Rails.logger.info "Reactivated #{reactivated} standup participants for #{platform_user_id}"
    return if reactivated.zero?

    ChatPlatform.for(platform).send_direct_message(platform_user_id, "Welcome back! You've been automatically re-enabled for standups.")
  end
end

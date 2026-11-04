# Ends someone's `away` period on any platform.
class ParticipantReactivationJob < ApplicationJob
  queue_as :default

  # return_date (ISO date) is the away period this job ends. Rows paused without
  # an away date are left alone. Rows whose away date has since moved later (a
  # newer `away`, or a manager changing the date in the console) get this job
  # again for that date, so a job cut short by `back` can't end a newer away
  # period early, and an extended one still ends.
  def perform(platform_user_id, participant_ids = nil, platform = ChatPlatform::DEFAULT.to_s, return_date = nil)
    # Only reactivate the participants the away command deactivated, when known.
    participants = StandupParticipant.on_platform(platform).where(platform_user_id: platform_user_id, active: false)
    participants = participants.where(id: participant_ids) if participant_ids.present?

    if return_date.present?
      return_date = Date.iso8601(return_date)
      reschedule_extended(participants.where(vacation_until: return_date.next_day..), platform_user_id, platform)
      participants = participants.where(vacation_until: ..return_date)
    end

    reactivated = participants.update_all(active: true, vacation_until: nil)
    Rails.logger.info "Reactivated #{reactivated} standup participants for #{platform_user_id}"
    return if reactivated.zero?

    ChatPlatform.for(platform).send_direct_message(platform_user_id, "Welcome back! You've been automatically re-enabled for standups.")
  end

  private

  # One job per later date, at the start of that day in the person's timezone.
  # A newer `away` has already queued its own; the extra one finds nothing to do.
  def reschedule_extended(participants, platform_user_id, platform)
    participants.includes(:standup).group_by(&:vacation_until).each do |date, rows|
      self.class
        .set(wait_until: date.in_time_zone(rows.first.standup_time_zone))
        .perform_later(platform_user_id, rows.map(&:id), platform, date.iso8601)
    end
  end
end

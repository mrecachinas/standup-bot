# Ends someone's `away` period on any platform.
class ParticipantReactivationJob < ApplicationJob
  queue_as :default

  # last_day_away (ISO date) is the end of the away period this job closes:
  # vacation_until, which is the last day without prompts (the console's
  # "through this date"). Only rows whose away period has ended by then are
  # reactivated. Rows paused without a date are left alone, and rows whose
  # away period has since moved later (a newer `away`, or a manager changing
  # the date in the console) get this job again for the day after their new
  # last day, so a job cut short by `back` can't end a newer away period
  # early, and an extended one still ends.
  #
  # Jobs queued before last_day_away existed have three arguments; they run
  # on their return day, so today is a safe cutoff for them.
  def perform(platform_user_id, participant_ids = nil, platform = ChatPlatform::DEFAULT.to_s, last_day_away = nil)
    last_day_away = last_day_away.present? ? Date.iso8601(last_day_away) : Date.current
    # Only reactivate the participants the away command deactivated, when known.
    participants = StandupParticipant.on_platform(platform).where(platform_user_id: platform_user_id, active: false)
    participants = participants.where(id: participant_ids) if participant_ids.present?

    reschedule_extended(participants.where(vacation_until: last_day_away.next_day..), platform_user_id, platform)

    reactivated = participants.where(vacation_until: ..last_day_away).update_all(active: true, vacation_until: nil)
    Rails.logger.info "Reactivated #{reactivated} standup participants for #{platform_user_id}"
    return if reactivated.zero?

    ChatPlatform.for(platform).send_direct_message(platform_user_id, "Welcome back! You've been automatically re-enabled for standups.")
  end

  private

  # One job per later date, at the start of the following day in the
  # person's timezone. A newer `away` has already queued its own; the extra
  # one finds nothing to do.
  def reschedule_extended(participants, platform_user_id, platform)
    participants.group_by(&:vacation_until).each do |date, rows|
      self.class
        .set(wait_until: date.next_day.in_time_zone(rows.first.time_zone))
        .perform_later(platform_user_id, rows.map(&:id), platform, date.iso8601)
    end
  end
end

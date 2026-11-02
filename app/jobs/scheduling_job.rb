class SchedulingJob < ApplicationJob
  queue_as :default

  # Window within which to schedule standup messages (slightly more than interval)
  SCHEDULING_WINDOW = 75.minutes

  def perform
    standups = Standup.active
    scheduled_count = 0

    standups.each do |standup|
      standup.standup_participants.active.each do |participant|
        send_at = participant.calculate_send_time
        occurrence = participant.next_standup_occurrence

        # Only schedule if within the next scheduling window to avoid duplicates
        next unless send_at.present? && send_at <= Time.current + SCHEDULING_WINDOW

        standup_date = occurrence_for_send_time?(occurrence, send_at) ? occurrence.standup_date : participant.standup_date_for(send_at)
        if standup.skips_occurrence_on?(standup_date)
          Rails.logger.info "Skipping standup #{standup.id} for #{standup_date}; schedule exception or holiday"
          next
        end

        unless participant.available_on?(standup_date)
          Rails.logger.info "Skipping participant #{participant.platform_user_id} for #{standup_date}; unavailable"
          next
        end

        if StandupResponse
            .where(platform_user_id: participant.platform_user_id, standup_id: standup.id)
            .for_standup_date(standup_date)
            .exists?
          Rails.logger.info "Skipping participant #{participant.platform_user_id}; response already exists for #{standup_date}"
          next
        end

        StandupMessageJob.set(wait_until: send_at).perform_later(participant.platform_user_id, standup.id, standup_date.iso8601)
        scheduled_count += 1
      end
    end

    StandupMetrics.track("scheduling.completed", active_standups: standups.count, messages_scheduled: scheduled_count)
  end

  private

  def occurrence_for_send_time?(occurrence, send_at)
    occurrence&.scheduled_at.present? && occurrence.scheduled_at.to_i == send_at.to_i
  end
end

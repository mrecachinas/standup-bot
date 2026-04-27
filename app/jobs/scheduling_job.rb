class SchedulingJob < ApplicationJob
  queue_as :default

  # Window within which to schedule standup messages (slightly more than interval)
  SCHEDULING_WINDOW = 75.minutes

  def perform
    Rails.logger.info "Starting scheduling job to process active standups"

    # Find all active standups
    standups = Standup.active
    Rails.logger.info "Found #{standups.count} active standups to schedule"
    scheduled_count = 0

    standups.each do |standup|
      Rails.logger.info "Processing standup: #{standup.id} - #{standup.name}"

      # Get all participants for this standup
      participants = standup.standup_participants.active
      Rails.logger.info "Found #{participants.count} active participants for standup #{standup.id}"

      participants.each do |participant|
        # Calculate send time using participant method
        send_at = participant.calculate_send_time

        # Only schedule if within the next scheduling window to avoid duplicates
        next unless send_at.present? && send_at <= Time.current + SCHEDULING_WINDOW

        standup_date = participant.standup_date_for(send_at)
        if standup.holiday_on?(standup_date)
          Rails.logger.info "Skipping standup #{standup.id} for #{standup_date}; configured holiday"
          next
        end

        unless participant.available_on?(standup_date)
          Rails.logger.info "Skipping participant #{participant.slack_id} for #{standup_date}; unavailable"
          next
        end

        if StandupResponse
            .where(slack_id: participant.slack_id, standup_id: standup.id)
            .for_standup_date(standup_date, participant.standup_time_zone)
            .exists?
          Rails.logger.info "Skipping participant #{participant.slack_id}; response already exists for #{standup_date}"
          next
        end

        Rails.logger.info "Scheduling standup message for participant #{participant.slack_id} at #{send_at}"

        # Schedule the standup message job
        StandupMessageJob.set(wait_until: send_at).perform_later(participant.slack_id, standup.id, standup_date.iso8601)
        scheduled_count += 1
      end
    end

    StandupMetrics.track("scheduling.completed", active_standups: standups.count, messages_scheduled: scheduled_count)
    Rails.logger.info "Scheduling job completed successfully"
  end
end

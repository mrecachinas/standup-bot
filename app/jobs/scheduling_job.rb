class SchedulingJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting scheduling job to process active standups"

    # Find all active standups
    standups = Standup.where(active: true)
    Rails.logger.info "Found #{standups.count} active standups to schedule"

    standups.each do |standup|
      Rails.logger.info "Processing standup: #{standup.id} - #{standup.name}"

      # Get all participants for this standup
      participants = standup.standup_participants.where(active: true)
      Rails.logger.info "Found #{participants.count} active participants for standup #{standup.id}"

      participants.each do |participant|
        # Calculate send time using participant method
        send_at = participant.calculate_send_time

        Rails.logger.info "Scheduling standup message for participant #{participant.slack_id} at #{send_at}"

        # Schedule the standup message job
        StandupMessageJob.set(wait_until: send_at).perform_later(participant.slack_id, standup.id)
      end
    end

    Rails.logger.info "Scheduling job completed successfully"
  end
end

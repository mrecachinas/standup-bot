class StandupMessageJob < ApplicationJob
  queue_as :default

  def perform(slack_id, standup_id, standup_date = nil)
    Rails.logger.info "Sending standup message to user #{slack_id} for standup #{standup_id}"

    standup = Standup.find(standup_id)
    Rails.logger.info "Found standup: #{standup.name}"

    participant = standup.standup_participants.find_by(slack_id: slack_id)
    lock_record = participant || standup

    lock_record.with_lock do
      resolved_standup_date = resolve_standup_date(standup_date, participant)

      if standup.skips_occurrence_on?(resolved_standup_date)
        Rails.logger.info "Skipping standup #{standup_id} for #{resolved_standup_date}; schedule exception or holiday"
        StandupMetrics.track("standup.skipped_schedule_exception", standup_id: standup_id, slack_id: slack_id)
        return
      end

      if participant.present? && !participant.available_on?(resolved_standup_date)
        Rails.logger.info "Skipping participant #{slack_id} for #{resolved_standup_date}; unavailable"
        StandupMetrics.track("standup.skipped_unavailable", standup_id: standup_id, slack_id: slack_id)
        return
      end

      if existing_response?(slack_id, standup_id, resolved_standup_date, participant)
        Rails.logger.info "User #{slack_id} already has a response for standup #{standup_id} on #{resolved_standup_date}, skipping"
        StandupMetrics.track("standup.skipped_existing_response", standup_id: standup_id, slack_id: slack_id)
        return
      end

      # Cancel any previous pending responses for this user in this standup
      StandupResponseService.cancel_previous_pending_responses(
        slack_id,
        standup_id,
        resolved_standup_date,
        response_time_zone_for(participant)
      )

      # Format intro with the first question
      first_question = standup.questions.first
      formatted_question = StandupFormatter.format_question(
        first_question,
        1,
        standup.questions.size
      )

      message_text = [
        standup.intro,
        "",
        formatted_question
      ].join("\n")

      # Use the inherited slack_client
      Rails.logger.info "Sending initial standup question to user #{slack_id}"
      message_response = slack_client.send_message(slack_id, message_text)
      message_channel = response_value(message_response, "channel") || slack_id
      Rails.logger.info "Message sent successfully to channel: #{message_channel}"

      # Create a pending standup response record
      standup_response = StandupResponse.create!(
        slack_id: slack_id,
        standup_id: standup_id,
        status: "pending",
        slack_channel: message_channel,
        standup_date: resolved_standup_date,
        answers: []
      )
      Rails.logger.info "Created pending standup response with ID: #{standup_response.id}"
      StandupMetrics.track("standup.sent", standup_id: standup_id, slack_id: slack_id, response_id: standup_response.id)
    end
  end

  private

  def existing_response?(slack_id, standup_id, standup_date, participant)
    StandupResponse
      .where(slack_id: slack_id, standup_id: standup_id)
      .for_standup_date(standup_date, response_time_zone_for(participant))
      .exists?
  end

  def resolve_standup_date(standup_date, participant)
    return Date.iso8601(standup_date.to_s) if standup_date.present?

    participant&.standup_date_for(Time.current) || response_time_zone_for(participant).today
  rescue ArgumentError
    response_time_zone_for(participant).today
  end

  def response_time_zone_for(participant)
    participant&.standup_time_zone || Time.zone
  end

  def response_value(response, key)
    return if response.blank?

    response[key] || response[key.to_sym]
  end
end

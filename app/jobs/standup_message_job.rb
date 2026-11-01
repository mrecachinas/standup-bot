class StandupMessageJob < ApplicationJob
  queue_as :default

  def perform(slack_id, standup_id, standup_date = nil)
    Rails.logger.info "Sending standup message to user #{slack_id} for standup #{standup_id}"

    standup = Standup.find(standup_id)

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

      StandupResponseService.cancel_previous_pending_responses(
        slack_id,
        standup_id,
        resolved_standup_date,
        response_time_zone_for(participant)
      )

      chat = chat_for(standup)
      formatted_question = StandupFormatter.format_question(
        standup.questions.first, 1, standup.questions.size, formatter: chat.formatter
      )
      message_text = [ standup.intro, "", formatted_question ].join("\n")

      message = chat.send_direct_message(slack_id, message_text)
      message_channel = message&.channel.presence || slack_id

      standup_response = StandupResponse.create!(
        slack_id: slack_id,
        standup_id: standup_id,
        status: "pending",
        slack_channel: message_channel,
        standup_date: resolved_standup_date,
        answers: []
      )
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
end

class StandupMessageJob < ApplicationJob
  queue_as :default

  # restart: replace a skipped or cancelled run for the day with a fresh one.
  def perform(platform_user_id, standup_id, standup_date = nil, restart: false)
    Rails.logger.info "Sending standup message to user #{platform_user_id} for standup #{standup_id}"

    standup = Standup.find(standup_id)

    participant = standup.standup_participants.find_by(platform_user_id: platform_user_id)
    lock_record = participant || standup

    lock_record.with_lock do
      resolved_standup_date = resolve_standup_date(standup_date, participant)

      if standup.skips_occurrence_on?(resolved_standup_date)
        Rails.logger.info "Skipping standup #{standup_id} for #{resolved_standup_date}; schedule exception or holiday"
        StandupMetrics.track("standup.skipped_schedule_exception", standup_id: standup_id, platform_user_id: platform_user_id)
        return
      end

      if participant.present? && !participant.available_on?(resolved_standup_date)
        Rails.logger.info "Skipping participant #{platform_user_id} for #{resolved_standup_date}; unavailable"
        StandupMetrics.track("standup.skipped_unavailable", standup_id: standup_id, platform_user_id: platform_user_id)
        return
      end

      discard_abandoned_response(platform_user_id, standup_id, resolved_standup_date) if restart

      if existing_response?(platform_user_id, standup_id, resolved_standup_date)
        Rails.logger.info "User #{platform_user_id} already has a response for standup #{standup_id} on #{resolved_standup_date}, skipping"
        StandupMetrics.track("standup.skipped_existing_response", standup_id: standup_id, platform_user_id: platform_user_id)
        return
      end

      wrapped_up = StandupResponseService.cancel_previous_pending_responses(
        platform_user_id,
        standup_id,
        resolved_standup_date
      )

      message = chat_for(standup).send_standup_kickoff(
        platform_user_id,
        standup_name: standup.name,
        channel: standup.platform_channel,
        channel_name: standup.platform_channel_name,
        intro: standup.intro,
        question: standup.questions.first,
        question_count: standup.questions.size,
        wrapped_up_previous: wrapped_up.to_i.positive?
      )
      message_channel = message&.channel.presence || platform_user_id

      standup_response = StandupResponse.create!(
        platform_user_id: platform_user_id,
        standup_id: standup_id,
        status: "pending",
        dm_channel: message_channel,
        standup_date: resolved_standup_date,
        answers: []
      )
      StandupMetrics.track("standup.sent", standup_id: standup_id, platform_user_id: platform_user_id, response_id: standup_response.id)
    end
  end

  private

  def discard_abandoned_response(platform_user_id, standup_id, standup_date)
    StandupResponse
      .where(platform_user_id: platform_user_id, standup_id: standup_id, status: %w[skipped cancelled])
      .for_standup_date(standup_date)
      .destroy_all
  end

  def existing_response?(platform_user_id, standup_id, standup_date)
    StandupResponse
      .where(platform_user_id: platform_user_id, standup_id: standup_id)
      .for_standup_date(standup_date)
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

class StandupMessageJob < ApplicationJob
  queue_as :default
  # When a standup goes out to everyone at once, only this many first messages
  # are sent at a time. Slack allows a workspace several hundred messages a
  # minute, and adding workers would only add rate-limit errors (whose retries
  # hold worker threads).
  limits_concurrency key: "send", to: ENV.fetch("STANDUP_SEND_CONCURRENCY", 2).to_i, duration: 5.minutes

  # restart: replace a skipped or cancelled run for the day with a fresh one.
  def perform(platform_user_id, standup_id, standup_date = nil, restart: false)
    Rails.logger.info "Sending standup message to user #{platform_user_id} for standup #{standup_id}"

    standup = Standup.find(standup_id)

    participant = standup.standup_participants.find_by(platform_user_id: platform_user_id)
    lock_record = participant || standup

    # Everything happens under the person's lock, so overlapping jobs can't
    # both start a run. The run is created only once the first DM is out, in
    # the same transaction, so a reply can't land in a run the person hasn't
    # seen, and a failed send leaves nothing behind for the retry to skip.
    # The lock is only contended by other first messages for this person.
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

      wrapped_up = StandupResponseService.cancel_previous_pending_responses(platform_user_id, standup_id, resolved_standup_date)
      message = send_kickoff(standup, participant, platform_user_id, resolved_standup_date, wrapped_up_previous: wrapped_up.to_i.positive?)

      standup_response = StandupResponse.create!(
        platform_user_id: platform_user_id,
        standup_id: standup_id,
        status: "pending",
        dm_channel: message&.channel.presence || platform_user_id,
        prompted_at: message&.sent_at || Time.current,
        standup_date: resolved_standup_date,
        answers: []
      )
      StandupMetrics.track("standup.sent", standup_id: standup_id, platform_user_id: platform_user_id, response_id: standup_response.id)
    end
  end

  private

  def send_kickoff(standup, participant, platform_user_id, standup_date, wrapped_up_previous:)
    chat_for(standup).send_standup_kickoff(
      platform_user_id,
      standup_name: standup.name,
      channel: standup.platform_channel,
      channel_name: standup.platform_channel_name,
      intro: standup.intro,
      question: standup.questions.first,
      question_count: standup.questions.size,
      first_name: first_name_for(participant),
      wrapped_up_previous: wrapped_up_previous,
      menu: StandupCommandHandler.kickoff_menu(standup.id, standup_date)
    )
  end

  # From the name stored for the participant, so sending standups doesn't
  # need a profile lookup per person (those are rate-limited).
  def first_name_for(participant)
    name = participant&.display_name
    name.to_s.split.first if name.present? && name != participant.platform_user_id
  end

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

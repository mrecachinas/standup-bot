class StandupReminderJob < ApplicationJob
  queue_as :default
  # A run that's still going when the next one starts (say, a burst of
  # reminders slowed by rate limits) makes the new one a no-op.
  limits_concurrency key: "run", on_conflict: :discard, duration: 15.minutes

  def perform(standup_id = nil)
    responses = StandupResponse.pending.includes(:standup)
    responses = responses.where(standup_id: standup_id) if standup_id.present?

    responses.find_each do |response|
      next unless reminder_due?(response)
      next if caught_up?(response)

      send_reminder(response)
    end
  end

  private

  def reminder_due?(response)
    standup = response.standup
    return false unless standup.active?
    return false unless standup.reminder_enabled?
    return false if standup.skips_occurrence_on?(response.standup_date)
    return false if response.reminder_count.to_i >= standup.max_reminders

    # Counted from the latest prompt or reminder, so someone who just got the
    # next question isn't reminded about it right away.
    reminder_reference = [ response.last_reminder_at, response.prompted_at ].compact.max || response.created_at
    reminder_reference <= standup.reminder_after_minutes.minutes.ago
  end

  # Before nudging someone on Slack, checks their DM for replies the bot missed
  # (see SlackDmBackfill). If there were any, they've moved on already.
  def caught_up?(response)
    return false unless response.standup.platform == "slack"

    SlackDmBackfill.new.call(response).positive?
  rescue StandardError => error
    raise if rate_limited?(error)

    Rails.logger.warn "Couldn't check #{response.platform_user_id}'s DM for missed replies: #{error.class} - #{error.message}"
    false
  end

  # The reminder is claimed before it's sent, so two runs (or a retry) can't
  # both send it, and given back if sending fails, so the next run tries again.
  # One person's failure doesn't stop the others' reminders, except a rate
  # limit, which ends the run for its retry.
  def send_reminder(response)
    count = response.reminder_count.to_i
    claimed = StandupResponse.pending.where(id: response.id, reminder_count: count)
      .update_all(reminder_count: count + 1, last_reminder_at: Time.current)
    return unless claimed == 1

    begin
      deliver_reminder(response)
    rescue StandardError => error
      StandupResponse.where(id: response.id).update_all(reminder_count: count, last_reminder_at: response.last_reminder_at)
      raise if rate_limited?(error)

      Rails.logger.error "Couldn't remind #{response.platform_user_id} about standup #{response.standup_id}: #{error.class} - #{error.message}"
      StandupMetrics.track("standup.reminder_failed", standup_id: response.standup_id, response_id: response.id, error_class: error.class.name)
    end
  end

  def deliver_reminder(response)
    standup = response.standup
    answered = response.answers&.size || 0
    total = standup.questions.size
    chat = chat_for(standup)
    fmt = chat.formatter
    question = standup.questions[answered]

    reminder = "⏰ #{fmt.bold(standup.name)} is still waiting on you (#{answered} of #{total} answered). " \
      "Reply here to pick up where you left off, or #{fmt.code("skip")} to pass on this one."
    chat.send_direct_message(
      response.platform_user_id,
      [ reminder, (StandupFormatter.format_question(question, formatter: fmt) if question.present?) ].compact.join("\n\n")
    )
  end

  def rate_limited?(error)
    error.is_a?(Slack::Web::Api::Errors::TooManyRequestsError) || error.is_a?(ChatPlatform::RateLimitedError)
  end
end

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

    Rails.error.report(error, context: { standup_response_id: response.id }, source: "standup_reminder_job.dm_backfill")
    false
  end

  # The reminder is claimed before it's sent by moving last_reminder_at to now,
  # only if the run hasn't changed since it was read (no other claim, answer
  # or prompt), so two runs or a retry can't both send it, and an answer
  # arriving meanwhile cancels a reminder that would repeat a question. The
  # count is used up only once it's delivered: a claim left by a worker that
  # stopped mid-send just delays the next try by the reminder interval. A
  # failed send gives the claim back. One person's failure doesn't stop the
  # others' reminders, except a rate limit, which ends the run for its retry.
  def send_reminder(response)
    previous = response.last_reminder_at
    claimed = StandupResponse.pending
      .where(id: response.id, reminder_count: response.reminder_count.to_i, last_reminder_at: previous,
        prompted_at: response.prompted_at, updated_at: response.updated_at)
      .update_all(last_reminder_at: Time.current)
    return unless claimed == 1

    begin
      deliver_reminder(response)
    rescue StandardError => error
      StandupResponse.where(id: response.id).update_all(last_reminder_at: previous)
      raise if rate_limited?(error)

      Rails.error.report(error, severity: :error, context: { standup_id: response.standup_id, standup_response_id: response.id }, source: "standup_reminder_job.remind")
      StandupMetrics.track("standup.reminder_failed", standup_id: response.standup_id, response_id: response.id, error_class: error.class.name)
      return
    end

    StandupResponse.where(id: response.id).update_all("reminder_count = reminder_count + 1")
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

class StandupAnalyticsService
  COMMON_WORDS = %w[
    a an and are as at be been but by for from had has have i in is it my no none not of on or our
    the this to today was we were with working
  ].freeze

  attr_reader :standup, :period_days

  def initialize(standup, period_days: 30, now: Time.current)
    @standup = standup
    @period_days = period_days.to_i.clamp(1, 365)
    @now = now
  end

  def summary
    {
      standup_id: standup.id,
      standup_name: standup.name,
      period_days: period_days,
      period_start: period_start.iso8601,
      period_end: now.iso8601,
      active_participants: active_participants.count,
      expected_responses: expected_responses,
      completed_responses: completed_responses.count,
      completion_rate: completion_rate,
      average_response_time_minutes: average_response_time_minutes(completed_responses),
      participant_stats: participant_stats,
      status_counts: responses.group(:status).count
    }
  end

  def completion_rate
    return 0.0 if expected_responses.zero?

    ((completed_responses.count.to_f / expected_responses) * 100).round(1)
  end

  def participant_stats
    expected_per_participant = expected_occurrences

    active_participants.order(:slack_name, :slack_id).map do |participant|
      participant_responses = responses.where(slack_id: participant.slack_id)
      participant_completed = participant_responses.where(status: "completed")

      {
        slack_id: participant.slack_id,
        slack_name: participant.slack_name,
        completed: participant_completed.count,
        expected: expected_per_participant,
        completion_rate: percentage(participant_completed.count, expected_per_participant),
        average_response_time_minutes: average_response_time_minutes(participant_completed)
      }
    end
  end

  def response_trends
    period_dates.map do |date|
      day_range = date.beginning_of_day..date.end_of_day
      day_responses = standup.standup_responses.where(created_at: day_range)
      completed_count = day_responses.where(status: "completed").count
      expected_count = scheduled_on?(date) ? active_participants.count : 0

      {
        date: date.iso8601,
        expected: expected_count,
        total: day_responses.count,
        completed: completed_count,
        completion_rate: percentage(completed_count, expected_count),
        statuses: day_responses.group(:status).count
      }
    end
  end

  def blocker_keywords(limit: 5)
    words = blocker_answers.flat_map do |answer|
      normalize_words(answer)
    end

    words.tally.sort_by { |word, count| [ -count, word ] }.first(limit).map do |word, count|
      { keyword: word, count: count }
    end
  end

  private

  attr_reader :now

  def period_start
    period_days.days.ago(now)
  end

  def responses
    @responses ||= standup.standup_responses.where(created_at: period_start..now)
  end

  def completed_responses
    @completed_responses ||= responses.where(status: "completed")
  end

  def active_participants
    @active_participants ||= standup.standup_participants.active
  end

  def expected_responses
    active_participants.count * expected_occurrences
  end

  def expected_occurrences
    @expected_occurrences ||= period_dates.count { |date| scheduled_on?(date) }
  end

  def period_dates
    (period_start.to_date..now.to_date).to_a
  end

  def scheduled_on?(date)
    case standup.schedule_type
    when "daily"
      true
    when "weekdays"
      date.on_weekday?
    when "weekly"
      schedule_days.include?(date.wday)
    when "biweekly"
      schedule_days.include?(date.wday) && (((date - Date.new(2024, 1, 1)).to_i / 7).even?)
    when "monthly"
      monthly_scheduled_on?(date)
    else
      false
    end
  end

  def schedule_days
    days = Array(standup.schedule_days).map(&:to_i)
    days.presence || [ 1 ]
  end

  def monthly_scheduled_on?(date)
    date.day == [ schedule_days.first, date.end_of_month.day ].min
  end

  def average_response_time_minutes(relation)
    durations = relation.map do |response|
      next unless response.created_at && response.updated_at

      duration = response.updated_at - response.created_at
      duration.positive? ? duration / 60.0 : nil
    end.compact

    return nil if durations.empty?

    (durations.sum / durations.size).round(1)
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end

  def blocker_answers
    completed_responses.flat_map do |response|
      Array(response.answers).filter_map do |answer|
        question = answer["question"] || answer[:question]
        text = answer["answer"] || answer[:answer]
        next unless question.to_s.match?(/block|impediment|stuck/i)
        next if text.blank? || text == "(skipped)"

        text
      end
    end
  end

  def normalize_words(text)
    text.downcase.scan(/[a-z][a-z0-9']+/).reject do |word|
      word.length < 3 || COMMON_WORDS.include?(word) || %w[none nope nothing skipped blocker blockers].include?(word)
    end
  end
end

require "csv"

class StandupAnalyticsService
  DEFAULT_PERIOD_DAYS = 30
  MAX_RANGE_DAYS = 365
  CSV_HEADERS = [
    "Date",
    "Standup",
    "Slack ID",
    "Participant",
    "Expected",
    "Status",
    "Submitted At",
    "Completed At",
    "Response Time Minutes",
    "Question",
    "Answer"
  ].freeze

  COMMON_WORDS = %w[
    a an and are as at be been but by for from had has have i in is it my no none not of on or our
    the this to today was we were with working
  ].freeze

  attr_reader :standup, :period_days, :start_date, :end_date

  def initialize(standup, period_days: DEFAULT_PERIOD_DAYS, now: Time.current, start_date: nil, end_date: nil)
    @standup = standup
    @period_days = period_days.to_i.clamp(1, MAX_RANGE_DAYS)
    @now = now
    @explicit_date_range = start_date.present? || end_date.present?
    @end_date = parse_date(end_date) || now.to_date
    @start_date = parse_date(start_date) || default_start_date
    @start_date, @end_date = normalize_range(@start_date, @end_date)
  end

  def summary
    {
      standup_id: standup.id,
      standup_name: standup.name,
      period_days: period_days,
      period_start: period_start.iso8601,
      period_end: period_end.iso8601,
      start_date: start_date.iso8601,
      end_date: end_date.iso8601,
      active_participants: active_participants.count,
      expected_responses: expected_responses,
      completed_responses: completed_responses.count,
      completion_rate: completion_rate,
      average_response_time_minutes: average_response_time_minutes(completed_responses),
      participant_stats: participant_stats,
      status_counts: status_counts
    }
  end

  def completion_rate
    percentage(completed_responses.count, expected_responses)
  end

  def participant_stats
    @participant_stats ||= active_participants.map do |participant|
      participant_responses = responses.select { |response| response.slack_id == participant.slack_id }
      participant_completed = participant_responses.select { |response| response.status == "completed" }
      expected = expected_dates_for(participant).count
      completed = participant_completed.count

      {
        slack_id: participant.slack_id,
        slack_name: participant.slack_name,
        completed: completed,
        expected: expected,
        missed: [ expected - completed, 0 ].max,
        completion_rate: percentage(completed, expected),
        average_response_time_minutes: average_response_time_minutes(participant_completed),
        last_response_at: participant_completed.filter_map(&:updated_at).max&.iso8601
      }
    end
  end

  def response_trends
    period_dates.map do |date|
      day_responses = responses_by_date.fetch(date, {}).values
      completed_count = day_responses.count { |response| response.status == "completed" }
      expected_count = expected_count_for(date)

      {
        date: date.iso8601,
        expected: expected_count,
        total: day_responses.count,
        completed: completed_count,
        completion_rate: percentage(completed_count, expected_count),
        statuses: tally_statuses(day_responses)
      }
    end
  end

  def frequent_non_responders(limit: 5)
    participant_stats
      .select { |stat| stat[:missed].positive? }
      .sort_by { |stat| [ -stat[:missed], stat[:completion_rate], stat[:slack_name].to_s.downcase, stat[:slack_id] ] }
      .first(limit)
  end

  def question_summaries(limit: 3)
    completed_count = completed_responses.count

    questions.map do |question|
      answers = answers_for_question(question)
      answered_answers = answers.reject { |entry| skipped_answer?(entry[:answer]) }

      {
        question: question,
        responses: answers.count,
        answered: answered_answers.count,
        skipped: answers.count - answered_answers.count,
        answer_rate: percentage(answered_answers.count, completed_count),
        common_keywords: keywords_for(answered_answers.map { |entry| entry[:answer] }, limit: 5),
        latest_answers: latest_answers(answered_answers, limit: limit)
      }
    end
  end

  def blocker_keywords(limit: 5)
    keywords_for(blocker_answers, limit: limit)
  end

  def csv_rows
    period_dates.flat_map do |date|
      responses_for_date = responses_by_date.fetch(date, {})
      export_participants_for(date, responses_for_date).flat_map do |participant|
        response = responses_for_date[participant.slack_id]
        build_csv_rows(date, participant, response)
      end
    end
  end

  def to_csv
    CSV.generate(headers: true) do |csv|
      csv << CSV_HEADERS
      csv_rows.each do |row|
        csv << CSV_HEADERS.map { |header| row.fetch(header) }
      end
    end
  end

  def range_limited?
    @range_limited || false
  end

  private

  Participant = Struct.new(:slack_id, :slack_name, :record, keyword_init: true) do
    def label
      slack_name.presence || slack_id
    end

    def available_on?(date)
      record&.available_on?(date) || false
    end
  end

  attr_reader :now

  def parse_date(value)
    return if value.blank?
    return value.to_date if value.respond_to?(:to_date)

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def default_start_date
    period_days.days.ago(now).to_date
  end

  def normalize_range(start_date, end_date)
    start_date, end_date = end_date, start_date if start_date > end_date

    if (end_date - start_date).to_i >= MAX_RANGE_DAYS
      @range_limited = true
      start_date = end_date - (MAX_RANGE_DAYS - 1)
    end

    [ start_date, end_date ]
  end

  def period_start
    explicit_date_range? ? start_date.beginning_of_day : period_days.days.ago(now)
  end

  def period_end
    explicit_date_range? ? end_date.end_of_day : now
  end

  def explicit_date_range?
    @explicit_date_range
  end

  def responses
    @responses ||= standup.standup_responses
      .where(
        "(standup_date BETWEEN :start_date AND :end_date) OR (standup_date IS NULL AND created_at BETWEEN :start_time AND :end_time)",
        start_date: start_date,
        end_date: end_date,
        start_time: period_start,
        end_time: period_end
      )
      .order(:created_at)
      .to_a
  end

  def responses_by_date
    @responses_by_date ||= responses.group_by { |response| response_date(response) }.transform_values do |date_responses|
      date_responses.group_by(&:slack_id).transform_values do |participant_responses|
        participant_responses.max_by { |response| [ response.updated_at || response.created_at, response.created_at ] }
      end
    end
  end

  def response_date(response)
    response.standup_date || response.created_at.in_time_zone.to_date
  end

  def completed_responses
    @completed_responses ||= responses.select { |response| response.status == "completed" }
  end

  def active_participants
    @active_participants ||= standup.standup_participants.active.order(:slack_name, :slack_id).to_a
  end

  def all_participants
    @all_participants ||= standup.standup_participants.order(:slack_name, :slack_id).to_a
  end

  def participants_by_slack_id
    @participants_by_slack_id ||= all_participants.index_by(&:slack_id)
  end

  def participant_for(slack_id)
    record = participants_by_slack_id[slack_id]

    Participant.new(slack_id: slack_id, slack_name: record&.slack_name, record: record)
  end

  def expected_responses
    @expected_responses ||= period_dates.sum { |date| expected_count_for(date) }
  end

  def expected_count_for(date)
    return 0 unless scheduled_on?(date)

    active_participants.count { |participant| participant.available_on?(date) }
  end

  def expected_dates_for(participant)
    period_dates.select { |date| scheduled_on?(date) && participant.available_on?(date) }
  end

  def period_dates
    @period_dates ||= (start_date..end_date).to_a
  end

  def status_counts
    tally_statuses(responses)
  end

  def tally_statuses(collection)
    collection.group_by(&:status).transform_values(&:count)
  end

  def scheduled_on?(date)
    standup.scheduled_on_date?(date)
  end

  def schedule_days
    days = Array(standup.schedule_days).filter_map { |day| Integer(day, exception: false) }
    days.presence || [ 1 ]
  end

  def biweekly_week?(date)
    week_start = date.beginning_of_week(:monday)
    ((week_start - Standup::BIWEEKLY_REFERENCE_DATE) / 7).to_i.even?
  end

  def monthly_scheduled_on?(date)
    date.day == [ schedule_days.first, date.end_of_month.day ].min
  end

  def average_response_time_minutes(collection)
    durations = collection.filter_map { |response| response_time_minutes(response) }

    return nil if durations.empty?

    (durations.sum / durations.size).round(1)
  end

  def response_time_minutes(response)
    return unless response&.created_at && response&.updated_at

    duration = response.updated_at - response.created_at
    duration.positive? ? (duration / 60.0).round(1) : nil
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end

  def questions
    @questions ||= (Array(standup.questions).map(&:to_s) + completed_responses.flat_map { |response|
      normalized_answers(response).map { |answer| answer[:question] }
    }).reject(&:blank?).uniq
  end

  def answers_for_question(question)
    completed_responses.flat_map do |response|
      normalized_answers(response).filter_map do |answer|
        next unless answer[:question] == question

        answer.merge(response: response)
      end
    end
  end

  def normalized_answers(response)
    Array(response.answers).filter_map do |answer|
      next unless answer.respond_to?(:[])

      {
        question: answer_value(answer, "question").to_s,
        answer: answer_value(answer, "answer").to_s,
        timestamp: answer_value(answer, "timestamp")
      }
    end
  end

  def answer_value(answer, key)
    answer[key] || answer[key.to_sym]
  end

  def skipped_answer?(answer)
    answer.blank? || answer.to_s.strip == "(skipped)"
  end

  def latest_answers(entries, limit:)
    entries
      .sort_by { |entry| answer_time(entry) || Time.zone.at(0) }
      .reverse
      .first(limit)
      .map do |entry|
        response = entry[:response]
        {
          slack_id: response.slack_id,
          slack_name: participant_for(response.slack_id).label,
          answer: entry[:answer].to_s.squish,
          submitted_at: response.created_at&.iso8601,
          answered_at: answer_time(entry)&.iso8601
        }
      end
  end

  def answer_time(entry)
    timestamp = entry[:timestamp]
    return timestamp.in_time_zone if timestamp.respond_to?(:in_time_zone)
    return entry[:response]&.updated_at if timestamp.blank?

    Time.zone.parse(timestamp.to_s)
  rescue ArgumentError, TypeError
    entry[:response]&.updated_at
  end

  def blocker_answers
    completed_responses.flat_map do |response|
      normalized_answers(response).filter_map do |answer|
        next unless answer[:question].match?(/block|impediment|stuck/i)
        next if skipped_answer?(answer[:answer])

        answer[:answer]
      end
    end
  end

  def keywords_for(texts, limit:)
    words = texts.flat_map { |text| normalize_words(text) }

    words.tally.sort_by { |word, count| [ -count, word ] }.first(limit).map do |word, count|
      { keyword: word, count: count }
    end
  end

  def normalize_words(text)
    text.to_s.downcase.scan(/[a-z][a-z0-9']+/).reject do |word|
      word.length < 3 || COMMON_WORDS.include?(word) || %w[none nope nothing skipped blocker blockers].include?(word)
    end
  end

  def export_participants_for(date, responses_for_date)
    expected_participants = active_participants.select { |participant| scheduled_on?(date) && participant.available_on?(date) }
    response_participants = responses_for_date.keys.map { |slack_id| participants_by_slack_id[slack_id] }.compact
    unknown_participants = responses_for_date.keys.reject { |slack_id| participants_by_slack_id.key?(slack_id) }

    ((expected_participants + response_participants).uniq.sort_by { |participant| [ participant.slack_name.to_s.downcase, participant.slack_id ] }.map do |participant|
      Participant.new(slack_id: participant.slack_id, slack_name: participant.slack_name, record: participant)
    end) + unknown_participants.sort.map { |slack_id| Participant.new(slack_id: slack_id, slack_name: nil, record: nil) }
  end

  def build_csv_rows(date, participant, response)
    answers = response ? normalized_answers(response) : []
    answers = [ { question: "", answer: "" } ] if answers.empty?

    answers.map do |answer|
      {
        "Date" => date.iso8601,
        "Standup" => standup.name,
        "Slack ID" => participant.slack_id,
        "Participant" => participant.label,
        "Expected" => expected_for_export?(date, participant) ? "yes" : "no",
        "Status" => export_status(date, participant, response),
        "Submitted At" => response&.created_at&.iso8601.to_s,
        "Completed At" => response&.status == "completed" ? response.updated_at&.iso8601.to_s : "",
        "Response Time Minutes" => response&.status == "completed" ? response_time_minutes(response).to_s : "",
        "Question" => answer[:question].to_s,
        "Answer" => answer[:answer].to_s
      }
    end
  end

  def expected_for_export?(date, participant)
    scheduled_on?(date) && participant.available_on?(date)
  end

  def export_status(date, participant, response)
    return response.status.titleize if response
    return "Missed" if expected_for_export?(date, participant)

    "Not expected"
  end
end

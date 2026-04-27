class StandupResponseHistory
  DEFAULT_RANGE_DAYS = 14
  MAX_RANGE_DAYS = 90

  Participant = Struct.new(:slack_id, :slack_name, :active, keyword_init: true) do
    def label
      return slack_id if slack_name.blank? || slack_name == slack_id

      "#{slack_name} (#{slack_id})"
    end

    def active?
      active
    end
  end

  Answer = Struct.new(:question, :text, :timestamp, keyword_init: true) do
    def timestamp_time
      return timestamp.in_time_zone if timestamp.respond_to?(:in_time_zone)
      return if timestamp.blank?

      Time.zone.parse(timestamp.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  Entry = Struct.new(:date, :participant, :expected, :response, :answers, keyword_init: true) do
    def slack_id
      participant.slack_id
    end

    def slack_name
      participant.slack_name.presence || participant.slack_id
    end

    def expected?
      expected
    end

    def answered?
      response&.status == "completed"
    end

    def missed?
      response.blank? && expected?
    end

    def status_label
      return "Missed" if missed?
      return "Not expected" unless response
      return "Answered" if answered?

      response.status.to_s.titleize
    end

    def submitted_at
      response&.created_at
    end

    def updated_at
      response&.updated_at
    end

    def updated_after_create?
      return false unless response&.created_at && response&.updated_at

      response.updated_at > response.created_at + 1.second
    end
  end

  Day = Struct.new(:date, :entries, keyword_init: true) do
    def expected_count
      entries.count(&:expected?)
    end

    def answered_count
      entries.count(&:answered?)
    end

    def missed_count
      entries.count(&:missed?)
    end
  end

  attr_reader :standup, :start_date, :end_date, :participant_slack_id, :question

  def initialize(standup:, params: {}, today: Time.zone.today)
    @standup = standup
    @params = params.to_h.with_indifferent_access
    @today = today.to_date
    @end_date = parse_date(@params[:end_date]) || @today
    @start_date = parse_date(@params[:start_date]) || (@end_date - (DEFAULT_RANGE_DAYS - 1))
    @start_date, @end_date = normalize_range(@start_date, @end_date)
    @participant_slack_id = @params[:participant].presence
    @question = @params[:question].presence
  end

  def days
    @days ||= history_dates.map do |date|
      Day.new(date: date, entries: entries_for(date))
    end.select { |day| day.entries.any? }
  end

  def participant_options
    @participant_options ||= begin
      known_options = all_participants.map { |participant| participant_option(participant) }
      known_slack_ids = known_options.map(&:slack_id)
      unknown_options = responses_in_range.map(&:slack_id).uniq.sort.filter_map do |slack_id|
        next if known_slack_ids.include?(slack_id)

        Participant.new(slack_id: slack_id, slack_name: nil, active: false)
      end

      known_options + unknown_options
    end
  end

  def question_options
    Array(standup.questions).map(&:to_s)
  end

  def summary
    entries = days.flat_map(&:entries)

    {
      dates: days.size,
      expected: entries.count(&:expected?),
      answered: entries.count(&:answered?),
      missed: entries.count(&:missed?)
    }
  end

  def range_limited?
    @range_limited || false
  end

  private

  def parse_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def normalize_range(start_date, end_date)
    start_date, end_date = end_date, start_date if start_date > end_date

    if (end_date - start_date).to_i >= MAX_RANGE_DAYS
      @range_limited = true
      start_date = end_date - (MAX_RANGE_DAYS - 1)
    end

    [ start_date, end_date ]
  end

  def all_participants
    @all_participants ||= standup.standup_participants.order(:slack_name, :slack_id).to_a
  end

  def participant_records_for_history
    records = all_participants
    return records if participant_slack_id.blank?

    records.select { |participant| participant.slack_id == participant_slack_id }
  end

  def participant_option(participant)
    Participant.new(
      slack_id: participant.slack_id,
      slack_name: participant.slack_name,
      active: participant.active?
    )
  end

  def history_dates
    @history_dates ||= (scheduled_dates + response_dates).uniq.sort.reverse
  end

  def scheduled_dates
    (start_date..end_date).select { |date| scheduled_on?(date) }
  end

  def response_dates
    responses_in_range.map { |response| response_date(response) }
  end

  def entries_for(date)
    responses_for_date = responses_by_date.fetch(date, {})
    participant_entries = participant_records_for_history.filter_map do |participant|
      response = responses_for_date[participant.slack_id]
      expected = participant.available_on?(date)
      next unless expected || response || participant_slack_id.present?

      build_entry(date, participant_option(participant), expected, response)
    end

    known_slack_ids = participant_entries.map(&:slack_id)
    unknown_entries = responses_for_date.keys.sort.filter_map do |slack_id|
      next if known_slack_ids.include?(slack_id)

      build_entry(
        date,
        Participant.new(slack_id: slack_id, slack_name: nil, active: false),
        false,
        responses_for_date[slack_id]
      )
    end

    (participant_entries + unknown_entries).sort_by { |entry| [ entry.slack_name.to_s.downcase, entry.slack_id ] }
  end

  def build_entry(date, participant, expected, response)
    Entry.new(
      date: date,
      participant: participant,
      expected: expected,
      response: response,
      answers: response ? answers_for(response) : []
    )
  end

  def responses_by_date
    @responses_by_date ||= responses_in_range.group_by { |response| response_date(response) }.transform_values do |responses|
      responses.group_by(&:slack_id).transform_values do |participant_responses|
        participant_responses.max_by { |response| [ response.updated_at || response.created_at, response.created_at ] }
      end
    end
  end

  def responses_in_range
    @responses_in_range ||= begin
      relation = standup.standup_responses.where(
        "(standup_date BETWEEN :start_date AND :end_date) OR (standup_date IS NULL AND created_at BETWEEN :start_time AND :end_time)",
        start_date: start_date,
        end_date: end_date,
        start_time: start_date.beginning_of_day,
        end_time: end_date.end_of_day
      )
      relation = relation.where(slack_id: participant_slack_id) if participant_slack_id.present?
      relation.order(created_at: :desc).to_a
    end
  end

  def response_date(response)
    response.standup_date || response.created_at.in_time_zone.to_date
  end

  def answers_for(response)
    Array(response.answers).filter_map do |answer|
      normalized_answer = normalize_answer(answer)
      next if question.present? && normalized_answer.question != question

      normalized_answer
    end
  end

  def normalize_answer(answer)
    Answer.new(
      question: answer_value(answer, "question").to_s,
      text: answer_value(answer, "answer").to_s,
      timestamp: answer_value(answer, "timestamp")
    )
  end

  def answer_value(answer, key)
    return unless answer.respond_to?(:[])

    answer[key] || answer[key.to_sym]
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
end

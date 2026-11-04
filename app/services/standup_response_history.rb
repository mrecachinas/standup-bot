class StandupResponseHistory
  DEFAULT_RANGE_DAYS = 14
  MAX_RANGE_DAYS = 90

  Participant = Struct.new(:platform_user_id, :display_name, :active, keyword_init: true) do
    def label
      return platform_user_id if display_name.blank? || display_name == platform_user_id

      "#{display_name} (#{platform_user_id})"
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

  Entry = Struct.new(:date, :participant, :expected, :upcoming, :response, :answers, keyword_init: true) do
    def platform_user_id
      participant.platform_user_id
    end

    def display_name
      participant.display_name.presence || participant.platform_user_id
    end

    def expected?
      expected
    end

    # Expected today (or later) but not prompted yet, so it isn't missed.
    def upcoming?
      upcoming
    end

    # Counts toward the expected total: an expected run that has gone out, or
    # anyone who got a prompt.
    def counted?
      (expected? && !upcoming?) || response.present?
    end

    def answered?
      response&.status == "completed"
    end

    def skipped?
      response&.status == "skipped"
    end

    def pending?
      response&.status == "pending"
    end

    def missed?
      counted? && !answered? && !skipped? && !pending?
    end

    def status_label
      return "Upcoming" if upcoming?
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
      entries.count(&:counted?)
    end

    def answered_count
      entries.count(&:answered?)
    end

    def missed_count
      entries.count(&:missed?)
    end
  end

  attr_reader :standup, :start_date, :end_date, :participant_id, :question

  def initialize(standup:, params: {}, today: Time.zone.today)
    @standup = standup
    @params = params.to_h.with_indifferent_access
    @today = today.to_date
    @range = ReportingRange.from_params(
      start_date: @params[:start_date],
      end_date: @params[:end_date],
      default_end: @today,
      default_start: ->(end_date) { end_date - (DEFAULT_RANGE_DAYS - 1) },
      max_days: MAX_RANGE_DAYS
    )
    @start_date = @range.start_date
    @end_date = @range.end_date
    @participant_id = @params[:participant].presence
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
      known_ids = known_options.map(&:platform_user_id)
      unknown_options = responses_in_range.map(&:platform_user_id).uniq.sort.filter_map do |platform_user_id|
        next if known_ids.include?(platform_user_id)

        Participant.new(platform_user_id: platform_user_id, display_name: nil, active: false)
      end

      known_options + unknown_options
    end
  end

  def question_options
    Array(standup.questions).map(&:to_s)
  end

  # answered + skipped + pending + missed always adds up to expected.
  def summary
    entries = days.flat_map(&:entries).select(&:counted?)

    {
      dates: days.size,
      expected: entries.size,
      answered: entries.count(&:answered?),
      skipped: entries.count(&:skipped?),
      pending: entries.count(&:pending?),
      missed: entries.count(&:missed?)
    }
  end

  def range_limited?
    @range.limited?
  end

  private

  def all_participants
    @all_participants ||= standup.standup_participants.order(:display_name, :platform_user_id).to_a
  end

  def participant_records_for_history
    records = all_participants
    return records if participant_id.blank?

    records.select { |participant| participant.platform_user_id == participant_id }
  end

  def participant_option(participant)
    Participant.new(
      platform_user_id: participant.platform_user_id,
      display_name: participant.display_name,
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
    responses_in_range.map(&:standup_date)
  end

  def entries_for(date)
    responses_for_date = responses_by_date.fetch(date, {})
    participant_entries = participant_records_for_history.filter_map do |participant|
      response = responses_for_date[participant.platform_user_id]
      expected = expected_on?(participant, date, response)
      next unless expected || response || participant_id.present?

      build_entry(date, participant_option(participant), expected, response)
    end

    known_ids = participant_entries.map(&:platform_user_id)
    unknown_entries = responses_for_date.keys.sort.filter_map do |platform_user_id|
      next if known_ids.include?(platform_user_id)

      build_entry(
        date,
        Participant.new(platform_user_id: platform_user_id, display_name: nil, active: false),
        false,
        responses_for_date[platform_user_id]
      )
    end

    (participant_entries + unknown_entries).sort_by { |entry| [ entry.display_name.to_s.downcase, entry.platform_user_id ] }
  end

  # Nobody is expected before the standup existed or they joined. On the day
  # they joined, a past run only counts if they got a prompt, since they may
  # have joined after it went out.
  def expected_on?(participant, date, response)
    return false unless participant.available_on?(date)

    first_date = first_expected_date_for(participant)
    return true if first_date.nil? || date > first_date
    return false if date < first_date

    response.present? || date >= @today
  end

  def first_expected_date_for(participant)
    @first_expected_dates ||= {}
    return @first_expected_dates[participant.platform_user_id] if @first_expected_dates.key?(participant.platform_user_id)

    @first_expected_dates[participant.platform_user_id] = participant.first_expected_date
  end

  def build_entry(date, participant, expected, response)
    Entry.new(
      date: date,
      participant: participant,
      expected: expected,
      upcoming: expected && response.blank? && date >= @today,
      response: response,
      answers: response ? answers_for(response) : []
    )
  end

  # { date => { platform_user_id => response } }; there's at most one per person per day.
  def responses_by_date
    @responses_by_date ||= responses_in_range.group_by(&:standup_date).transform_values { |responses| responses.index_by(&:platform_user_id) }
  end

  def responses_in_range
    @responses_in_range ||= begin
      relation = standup.standup_responses.where(standup_date: start_date..end_date)
      relation = relation.where(platform_user_id: participant_id) if participant_id.present?
      relation.order(created_at: :desc).to_a
    end
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
end

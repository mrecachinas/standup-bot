# The console's response history: one section per standup date, with each
# expected or responding person's status and answers.
class ResponseHistorySerializer
  def initialize(history, avatar_urls: {})
    @history = history
    @avatar_urls = avatar_urls
  end

  def as_json(*)
    {
      filters: {
        start_date: @history.start_date.iso8601,
        end_date: @history.end_date.iso8601,
        participant: @history.participant_id,
        question: @history.question
      },
      range_limited: @history.range_limited?,
      max_range_days: StandupResponseHistory::MAX_RANGE_DAYS,
      default_range_days: StandupResponseHistory::DEFAULT_RANGE_DAYS,
      summary: summary,
      participant_options: @history.participant_options.map do |participant|
        {
          platform_user_id: participant.platform_user_id,
          display_name: participant.display_name,
          label: participant.label,
          active: participant.active? || false
        }
      end,
      question_options: @history.question_options,
      days: @history.days.map { |day| serialize_day(day) }
    }
  end

  private

  def summary
    summary = @history.summary
    answer_rate = Percentage.of(summary[:answered], summary[:expected].to_i, empty: nil)
    summary.merge(answer_rate: answer_rate, answer_rate_tone: (UiFormat.rate_tone(answer_rate) if answer_rate))
  end

  def serialize_day(day)
    rate = Percentage.of(day.answered_count, day.expected_count)

    {
      date: day.date.iso8601,
      date_label: day.date.to_fs(:long),
      expected_count: day.expected_count,
      answered_count: day.answered_count,
      missed_count: day.missed_count,
      upcoming_count: day.entries.count(&:upcoming?),
      answer_rate: rate,
      answer_rate_tone: UiFormat.rate_tone(rate),
      entries: day.entries.map { |entry| serialize_entry(entry) }
    }
  end

  def serialize_entry(entry)
    avatar_url = @avatar_urls[entry.platform_user_id]

    {
      platform_user_id: entry.platform_user_id,
      display_name: entry.display_name,
      avatar_url: avatar_url,
      expected: entry.expected? || false,
      answered: entry.answered?,
      missed: entry.missed?,
      upcoming: entry.upcoming?,
      status: entry.response&.status,
      status_label: entry.status_label,
      status_tone: status_tone(entry),
      response_id: entry.response&.id,
      submitted_at: entry.submitted_at&.iso8601,
      submitted_at_label: entry.submitted_at&.to_fs(:long),
      updated_at: entry.updated_at&.iso8601,
      updated_at_label: entry.updated_at&.to_fs(:long),
      updated_after_create: entry.updated_after_create?,
      answers: entry.answers.map { |answer| serialize_answer(answer) },
      empty_message: empty_message(entry)
    }
  end

  def serialize_answer(answer)
    answered_at = answer.timestamp_time

    {
      question: answer.question,
      text: answer.text,
      display_text: answer.text.presence || "No answer provided.",
      timestamp: answer.timestamp.presence&.to_s,
      answered_at: answered_at&.iso8601,
      answered_at_label: answered_at&.to_fs(:long) || answer.timestamp.presence&.to_s
    }
  end

  def status_tone(entry)
    return "success" if entry.answered?
    return "info" if entry.pending?

    "warning" if entry.missed? || entry.skipped?
  end

  def empty_message(entry)
    return if entry.answers.any?
    return "Not sent yet." if entry.upcoming?
    return "No answer recorded for “#{@history.question}”." if entry.response && @history.question.present?
    return "No submitted answers were recorded for this response." if entry.response

    "No response submitted for this standup date."
  end
end

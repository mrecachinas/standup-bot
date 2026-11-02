# A standup's overview page: the last two weeks of completion, the runs behind
# the chart, the latest run's answers, who takes part, what's coming up, and
# any schedule exceptions.
class StandupOverviewSerializer
  include ActionView::Helpers::DateHelper

  PERIOD_DAYS = 14
  SIDEBAR_PARTICIPANT_LIMIT = 8

  def initialize(standup, preview_timezone: StandupSchedulePreviewSerializer::DEFAULT_TIMEZONE, now: Time.current)
    @standup = standup
    @preview_timezone = preview_timezone
    @now = now
  end

  def as_json(*)
    {
      period_days: PERIOD_DAYS,
      summary: summary_json,
      completion: completion_json,
      average_response_time: average_response_time_json,
      participant_counts: participant_counts,
      next_run: next_run_json,
      runs: runs.map { |run| run.merge(date: run[:date].iso8601) },
      runs_have_pending: runs.any? { |run| run[:pending].positive? },
      latest_run: latest_run_json,
      participants: participants.map { |participant| participant_json(participant) },
      sidebar_participants: active_participants.first(SIDEBAR_PARTICIPANT_LIMIT).map { |participant| participant_json(participant) },
      more_participants_count: [ active_participants.size - SIDEBAR_PARTICIPANT_LIMIT, 0 ].max,
      upcoming: upcoming_json,
      schedule_exceptions: schedule_exceptions.map { |exception| schedule_exception_json(exception) }
    }
  end

  private

  def analytics
    @analytics ||= StandupAnalyticsService.new(@standup, period_days: PERIOD_DAYS, now: @now)
  end

  def summary
    @summary ||= analytics.summary
  end

  def runs
    @runs ||= analytics.run_breakdown
  end

  def previous_completion_rate
    return @previous_completion_rate if defined?(@previous_completion_rate)

    previous = StandupAnalyticsService.new(
      @standup,
      now: @now,
      start_date: analytics.start_date - PERIOD_DAYS,
      end_date: analytics.start_date - 1
    )
    @previous_completion_rate = previous.responses? ? previous.completion_rate : nil
  end

  def summary_json
    summary.except(:participant_stats)
  end

  def completion_json
    has_runs = summary[:expected_responses].positive?
    rate = summary[:completion_rate]
    {
      rate: has_runs ? rate : nil,
      label: has_runs ? percent(rate) : "—",
      tone: (UiFormat.rate_tone(rate) if has_runs),
      completed: summary[:completed_responses],
      expected: summary[:expected_responses],
      sub_label: "#{summary[:completed_responses]} of #{summary[:expected_responses]} responses",
      previous_rate: previous_completion_rate,
      delta: (delta(rate, previous_completion_rate) if has_runs)
    }
  end

  def delta(current, previous)
    return if current.nil? || previous.nil?

    diff = (current.to_f - previous.to_f).round
    direction = if diff.zero? then "flat" elsif diff.positive? then "up" else "down" end
    arrow = if diff.zero? then "" elsif diff.positive? then "↑ " else "↓ " end
    { value: diff, direction: direction, label: "#{arrow}#{diff.abs} pts", title: "Compared with the previous period" }
  end

  def average_response_time_json
    minutes = summary[:average_response_time_minutes]
    {
      minutes: minutes,
      label: minutes ? distance_of_time_in_words(minutes.minutes) : "—"
    }
  end

  def participants
    @participants ||= @standup.standup_participants.order(:display_name, :platform_user_id).to_a
  end

  def active_participants
    @active_participants ||= participants.select(&:active?)
  end

  def participant_counts
    {
      total: participants.size,
      active: active_participants.size,
      inactive: participants.size - active_participants.size
    }
  end

  def participant_json(participant)
    ParticipantSerializer.new(participant).as_json.merge(
      timezone_label: participant.cached_timezone.to_s.split("/").last.to_s.tr("_", " ").presence
    )
  end

  def preview
    @preview ||= StandupSchedulePreviewSerializer.new(@standup, timezone: @preview_timezone)
  end

  def next_run_json
    occurrence = preview.occurrences.first if @standup.active?
    if occurrence
      local = occurrence.in_time_zone(preview.zone)
      {
        scheduled_at: occurrence.iso8601,
        label: local.strftime("%a, %b %-d"),
        sub_label: UiFormat.format_clock(@standup.default_hour, @standup.default_minute) +
          (@standup.respect_timezone? ? " in each person's timezone" : " UTC")
      }
    else
      {
        scheduled_at: nil,
        label: @standup.active? ? "—" : "Paused",
        sub_label: "Resume to schedule runs"
      }
    end
  end

  def upcoming_json
    preview.as_json.merge(
      paused: !@standup.active?,
      paused_message: ("This standup is paused. Resume it to schedule runs." unless @standup.active?),
      empty_message: preview.error || "No upcoming runs."
    )
  end

  def latest_run_responses
    @latest_run_responses ||= begin
      latest_date = @standup.standup_responses.maximum(:standup_date)
      latest_date ? @standup.standup_responses.where(standup_date: latest_date).to_a : []
    end
  end

  def latest_run_json
    latest_date = latest_run_responses.first&.standup_date
    participants_by_id = participants.index_by(&:platform_user_id)
    responses = latest_run_responses.sort_by { |response| participants_by_id[response.platform_user_id]&.display_name.to_s }

    {
      date: latest_date&.iso8601,
      date_label: latest_date ? latest_date.to_fs(:long) : "No runs yet",
      responses: responses.map { |response| latest_response_json(response, participants_by_id[response.platform_user_id]) }
    }
  end

  def latest_response_json(response, participant)
    status_label = response.status.to_s.titleize
    avatar_url = participant&.avatar_url
    {
      id: response.id,
      platform_user_id: response.platform_user_id,
      display_name: participant&.display_name.presence || response.platform_user_id,
      avatar_url: avatar_url,
      status: response.status,
      status_label: status_label,
      status_tone: UiFormat.status_tone(status_label),
      standup_date: response.standup_date&.iso8601,
      created_at: response.created_at&.iso8601,
      updated_at: response.updated_at&.iso8601,
      answers: Array(response.answers).map do |answer|
        { question: answer["question"] || answer[:question], answer: answer["answer"] || answer[:answer] }
      end
    }
  end

  def schedule_exceptions
    @standup.standup_schedule_exceptions.upcoming_first.to_a
  end

  def schedule_exception_json(exception)
    {
      id: exception.id,
      exception_type: exception.exception_type,
      label: exception.label,
      tone: UiFormat.status_tone(exception.label),
      original_date: exception.original_date&.iso8601,
      reason: exception.reason,
      rescheduled_at: exception.scheduled_at&.iso8601,
      blocks_occurrence: exception.blocks_occurrence?
    }
  end

  def percent(value)
    return "—" if value.nil?

    "#{value.round}%"
  end
end

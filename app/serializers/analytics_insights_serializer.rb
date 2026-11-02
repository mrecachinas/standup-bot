# Everything the console's Insights tab draws: headline stats with the change
# from the previous period, chart series, per-person participation, blockers,
# and per-question completion.
class AnalyticsInsightsSerializer
  RANGE_PRESETS = [ 7, 30, 90 ].freeze
  RUN_SEGMENTS = %i[completed skipped pending missed].freeze

  def initialize(analytics, previous: nil, today: Date.current)
    @analytics = analytics
    @previous = previous
    @today = today
  end

  def as_json(*)
    {
      range: range,
      has_data: summary[:expected_responses].positive?,
      stats: stats,
      runs: runs,
      runs_have_pending: runs.any? { |run| run[:pending].positive? },
      completion_series: completion_series,
      participants: participants,
      blocker_keywords: @analytics.blocker_keywords(limit: 10),
      question_funnel: question_funnel,
      question_summaries: question_summaries
    }
  end

  private

  def summary
    @summary ||= @analytics.summary
  end

  def range_days
    (@analytics.end_date - @analytics.start_date).to_i + 1
  end

  def range
    {
      start_date: @analytics.start_date.iso8601,
      end_date: @analytics.end_date.iso8601,
      days: range_days,
      label: "#{@analytics.start_date.to_fs(:month_day)} – #{@analytics.end_date.to_fs(:month_day_year)}",
      limited: @analytics.range_limited?,
      max_days: StandupAnalyticsService::MAX_RANGE_DAYS,
      presets: RANGE_PRESETS.map do |days|
        {
          days: days,
          label: "#{days} days",
          start_date: (@today - (days - 1)).iso8601,
          end_date: @today.iso8601,
          selected: range_days.between?(days, days + 1) && @analytics.end_date == @today
        }
      end
    }
  end

  def stats
    previous_rate = previous_completion_rate
    delta = (summary[:completion_rate].to_f - previous_rate.to_f).round unless previous_rate.nil?

    {
      completion_rate: summary[:completion_rate],
      previous_completion_rate: previous_rate,
      completion_rate_delta: delta,
      completion_rate_delta_direction: delta && (delta.zero? ? "flat" : (delta.positive? ? "up" : "down")),
      comparison_label: "vs. the previous #{range_days} #{"day".pluralize(range_days)}",
      completed_responses: summary[:completed_responses],
      expected_responses: summary[:expected_responses],
      active_participants: summary[:active_participants],
      average_response_time_minutes: summary[:average_response_time_minutes],
      average_response_time_label: summary[:average_response_time_minutes] ? "#{summary[:average_response_time_minutes].round} min" : nil,
      runs_count: runs.size
    }
  end

  def previous_completion_rate
    @previous.completion_rate if @previous&.responses?
  end

  def runs
    @runs ||= @analytics.run_breakdown.map do |run|
      pending = run[:pending].positive? ? ", #{run[:pending]} pending" : ""
      run.merge(
        date: run[:date].iso8601,
        label: run[:date].to_fs(:month_day),
        total: RUN_SEGMENTS.sum { |key| run[key].to_i },
        title: "#{run[:date].to_fs(:month_day_year)}: #{run[:completed]} completed, #{run[:skipped]} skipped, " \
          "#{run[:missed]} missed#{pending} (#{run[:completion_rate].round}%)"
      )
    end
  end

  def completion_series
    @analytics.run_breakdown.map do |run|
      {
        date: run[:date].iso8601,
        label: run[:date].to_fs(:month_day),
        value: run[:completion_rate],
        title: "#{run[:date].to_fs(:long)}: #{run[:completion_rate].round}% (#{run[:completed]}/#{run[:expected]})"
      }
    end
  end

  def participants
    summary[:participant_stats]
      .sort_by { |stat| [ stat[:completion_rate], stat[:display_name].to_s.downcase ] }
      .map do |stat|
        stat.merge(
          name: stat[:display_name].presence || stat[:platform_user_id],
          avatar_url: stat[:avatar_url],
          missed_label: stat[:missed].positive? ? "#{stat[:missed]} missed #{"response".pluralize(stat[:missed])}" : "No misses",
          rate_tone: UiFormat.rate_tone(stat[:completion_rate]),
          has_expected: stat[:expected].positive?
        )
      end
  end

  def question_funnel
    rows = @analytics.question_funnel
    started = rows.first&.dig(:started).to_i
    biggest_drop = rows.max_by { |row| row[:drop_off] }

    {
      started: started,
      started_label: "Out of #{started} #{"check-in".pluralize(started)} started in this period",
      biggest_drop: (biggest_drop.slice(:position, :question, :drop_off) if biggest_drop && biggest_drop[:drop_off].positive?),
      rows: rows
    }
  end

  def question_summaries
    @analytics.question_summaries(limit: 3).map do |question|
      question.merge(
        latest_answers: question[:latest_answers].map do |answer|
          answered_at = Time.zone.parse(answer[:answered_at].to_s) if answer[:answered_at].present?
          answer.merge(answered_at_label: answered_at&.to_fs(:month_day))
        end
      )
    end
  end
end

# The console's home page: totals across the standups someone manages, the
# team-wide responses-by-day chart, what needs attention, and one row per
# standup with its completion, trend, next run and latest run.
class OverviewDashboardSerializer
  include ActionView::Helpers::DateHelper

  VISIBILITY_OPTIONS = [
    { value: "all", label: "All" },
    { value: "active", label: "Active" },
    { value: "paused", label: "Paused" }
  ].freeze
  ATTENTION_LIMIT = 6
  TREND_POINTS = 10
  AVATAR_LIMIT = 4

  def initialize(dashboard, visibility:, period_days:)
    @dashboard = dashboard
    @visibility = visibility
    @period_days = period_days
  end

  def as_json(*)
    {
      visibility: @visibility,
      visibility_options: VISIBILITY_OPTIONS,
      period_days: @period_days,
      subtitle: "How your standups are doing over the last #{@period_days} #{"day".pluralize(@period_days)}.",
      empty: items.empty? && @visibility == "all",
      empty_list_message: "No #{@visibility} standups.",
      stats: stats,
      daily_totals: daily_totals.map { |row| row.merge(date: row[:date].iso8601) },
      daily_has_pending: daily_totals.any? { |row| row[:pending].positive? },
      needs_attention: attention.first(ATTENTION_LIMIT).map { |item| attention_json(item) },
      needs_attention_empty_message: "All standups are running and above 60% completion.",
      standups: items.map { |item| item_json(item) }
    }
  end

  private

  def items
    @items ||= @dashboard.items
  end

  def daily_totals
    @daily_totals ||= @dashboard.daily_totals
  end

  def attention
    @attention ||= items.select(&:needs_attention?)
  end

  def stats
    active_count = items.count { |item| item.standup.active? }
    paused_count = items.size - active_count
    expected = items.sum(&:expected_responses)
    completed = items.sum(&:completed_responses)
    rate = expected.positive? ? (completed * 100.0 / expected) : nil
    people_count = @dashboard.people_count

    {
      standups_count: items.size,
      active_count: active_count,
      paused_count: paused_count,
      paused_label: paused_count.positive? ? "#{paused_count} paused" : "None paused",
      people_count: people_count,
      people_label: "Across #{items.size} #{"standup".pluralize(items.size)}",
      expected_responses: expected,
      completed_responses: completed,
      completion_rate: rate,
      completion_rate_label: percent(rate),
      completion_tone: (UiFormat.rate_tone(rate) if rate),
      completion_sub_label: "#{completed.to_fs(:delimited)} of #{expected.to_fs(:delimited)} expected",
      needs_attention_count: attention.size,
      needs_attention_label: attention.any? ? "See list below" : "Everything looks healthy"
    }
  end

  def attention_json(item)
    {
      standup_id: item.standup.id,
      name: item.standup.name,
      active: item.standup.active?,
      reason: item.attention_reason,
      tone: item.standup.active? ? "danger" : "warning"
    }
  end

  def item_json(item)
    standup = item.standup
    rate = item.completion_rate
    has_runs = item.expected_responses.positive?
    next_occurrence = item.next_occurrence
    latest_status = item.latest_run_status

    StandupSerializer.new(standup).as_json.merge(
      standup_id: standup.id,
      participant_count: item.participant_count,
      participant_label: item.participant_count.positive? ? "#{item.participant_count} active #{"participant".pluralize(item.participant_count)}" : "None yet",
      participant_avatars: item.participant_avatars.map { |name, url| { name: name, avatar_url: (url if SlackAvatar.safe_url?(url)) } },
      avatar_limit: AVATAR_LIMIT,
      completion_rate: has_runs ? rate : nil,
      completion_rate_label: has_runs ? percent(rate) : nil,
      completion_tone: (UiFormat.rate_tone(rate) if has_runs),
      completed_responses: item.completed_responses,
      expected_responses: item.expected_responses,
      completion_sub_label: has_runs ? "#{item.completed_responses} of #{item.expected_responses} responses" : "No runs yet",
      trend_rates: item.trend_rates.last(TREND_POINTS),
      next_run: next_run_json(next_occurrence),
      latest_run_status: latest_status,
      latest_run_status_tone: UiFormat.status_tone(latest_status),
      latest_run_summary: item.latest_run_summary,
      latest_run_pending: latest_status == "Pending",
      needs_attention: item.needs_attention?,
      attention_reason: (item.attention_reason if item.needs_attention?)
    )
  end

  def next_run_json(occurrence)
    scheduled_at = occurrence&.scheduled_at
    return { scheduled_at: nil, label: "Not scheduled" } unless scheduled_at

    relative = scheduled_at.future? ? "in #{time_ago_in_words(scheduled_at)}" : "#{time_ago_in_words(scheduled_at)} ago"
    { scheduled_at: scheduled_at.iso8601, label: "Next #{relative}", title: scheduled_at.to_fs(:long) }
  end

  def percent(value)
    return "—" if value.nil?

    "#{value.round}%"
  end
end

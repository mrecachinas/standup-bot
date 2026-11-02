# The member's home page: one card per standup they're in, plus totals.
class MemberStandupsSerializer
  def initialize(member, summaries)
    @member = member
    @summaries = summaries
  end

  def as_json(*)
    away_until = @member.away_until
    {
      member: MemberProfileSerializer.new(@member).as_json,
      away_until: away_until&.iso8601,
      away_until_label: away_until&.strftime("%A, %B %-d"),
      stats: stats(away_until),
      standups: @summaries.map { |summary| summary_json(summary) }
    }
  end

  private

  def stats(away_until)
    rated = @summaries.select(&:stats)
    expected = rated.sum { |summary| summary.stats[:expected] }
    completed = rated.sum { |summary| summary.stats[:completed] }
    next_summary, next_at = @summaries.filter_map { |summary| [ summary, summary.next_check_in ] if summary.next_check_in }.min_by(&:last)

    {
      standups_count: @summaries.size,
      active_count: @summaries.count { |summary| summary.participant.active? && summary.standup.active? },
      period_days: MemberStandupSummary::PERIOD_DAYS,
      expected: expected,
      completed: completed,
      completion_rate: Percentage.of(completed, expected, empty: nil),
      next_check_in: next_at && {
        at: next_at.iso8601,
        standup_id: next_summary.standup.id,
        standup_name: next_summary.standup.name,
        date_label: next_at.strftime("%a, %b %-d"),
        time_label: next_at.strftime("%-l:%M %p %Z")
      },
      status_label: away_until ? "Away" : "Available",
      status_detail: away_until ? "Back #{(away_until + 1).strftime("%b %-d")}" : "Getting check-ins as scheduled"
    }
  end

  def summary_json(summary)
    standup = summary.standup
    participant = summary.participant
    status_label, status_tone = summary.status
    today = summary.today_response
    next_at = summary.next_check_in
    rate = summary.completion_rate

    {
      standup: {
        id: standup.id,
        name: standup.name,
        active: standup.active,
        platform: standup.platform,
        platform_label: standup.chat_platform.label,
        platform_channel: standup.platform_channel,
        platform_channel_name: standup.platform_channel_name,
        channel_reference: standup.channel_reference,
        schedule_summary: UiFormat.schedule_summary(standup)
      },
      participant: {
        id: participant.id,
        active: participant.active,
        vacation_until: participant.vacation_until&.iso8601
      },
      status_label: status_label,
      status_tone: status_tone,
      away: summary.away?,
      next_check_in: next_at&.iso8601,
      next_check_in_label: next_at&.strftime("%a, %b %-d at %-l:%M %p %Z"),
      today: today && response_status(today),
      completion_rate: rate,
      completion_rate_tone: rate && UiFormat.rate_tone(rate),
      stats: summary.stats&.slice(:expected, :completed, :missed),
      teammates: summary.teammates.map { |name, avatar_url| { name: name, avatar_url: (avatar_url if SlackAvatar.safe_url?(avatar_url)) } }
    }
  end

  def response_status(response)
    label = MemberResponsesSerializer.status_label(response)
    { id: response.id, status: response.status, status_label: label, status_tone: UiFormat.status_tone(label) }
  end
end

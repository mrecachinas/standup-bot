# What one member needs to know about one of their standups.
class MemberStandupSummary
  PERIOD_DAYS = 30

  attr_reader :participant

  delegate :standup, :platform_user_id, to: :participant

  def initialize(participant, now: Time.current)
    @participant = participant
    @now = now
  end

  def stats
    return @stats if defined?(@stats)

    @stats = analytics.participant_stats.find { |stat| stat[:platform_user_id] == platform_user_id }
  end

  def completion_rate
    stats && stats[:expected].positive? ? stats[:completion_rate] : nil
  end

  def next_check_in
    return unless standup.active? && participant.active?

    @next_check_in ||= participant.next_standup_occurrence&.scheduled_at&.in_time_zone(participant.standup_time_zone)
  rescue StandardError
    nil
  end

  def today_response
    return @today_response if defined?(@today_response)

    @today_response = standup.standup_responses.find_by(platform_user_id: platform_user_id, standup_date: participant.standup_date_for(@now))
  end

  def last_completed_at
    standup.standup_responses.where(platform_user_id: platform_user_id, status: "completed").maximum(:updated_at)
  end

  def teammates
    @teammates ||= standup.standup_participants.active.where.not(platform_user_id: platform_user_id).order(:display_name).pluck(:display_name, :avatar_url)
  end

  def away?
    participant.vacation_until.present? && participant.vacation_until >= @now.to_date
  end

  def status
    return [ "Not active", nil ] unless participant.active?
    return [ "Standup paused", "warning" ] unless standup.active?
    return [ "Away through #{participant.vacation_until.strftime("%b %-d")}", "warning" ] if away?

    [ "Active", "success" ]
  end

  private

  def analytics
    @analytics ||= StandupAnalyticsService.new(standup, period_days: PERIOD_DAYS, now: @now)
  end
end

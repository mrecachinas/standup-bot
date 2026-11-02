# The member's time away: where they're away now and which standups they can
# set time away on.
class MemberAvailabilitySerializer
  def initialize(member, max_away_days:, selected_standup_ids: nil, today: Date.current)
    @member = member
    @max_away_days = max_away_days
    @selected_standup_ids = selected_standup_ids
    @today = today
  end

  def as_json(*)
    active = @member.participants.select(&:active?)
    away = @member.participants.select { |participant| participant.vacation_until.present? && participant.vacation_until >= @today }
    selected = @selected_standup_ids.presence || active.map(&:standup_id)

    {
      member: MemberProfileSerializer.new(@member).as_json,
      today: @today.iso8601,
      min_date: @today.iso8601,
      max_date: (@today + @max_away_days).iso8601,
      max_away_days: @max_away_days,
      away: away.map do |participant|
        {
          participant_id: participant.id,
          standup_id: participant.standup_id,
          standup_name: participant.standup.name,
          vacation_until: participant.vacation_until.iso8601,
          vacation_until_label: participant.vacation_until.to_fs(:weekday_month_day)
        }
      end,
      standups: active.map do |participant|
        {
          participant_id: participant.id,
          standup_id: participant.standup_id,
          standup_name: participant.standup.name,
          selected: selected.include?(participant.standup_id)
        }
      end
    }
  end
end

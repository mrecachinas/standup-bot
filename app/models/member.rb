# A person who takes part in standups, identified by their Slack user ID.
# Members don't have a User record; they sign in with Slack.
class Member
  attr_reader :slack_id

  def self.for(slack_id, name: nil)
    return if slack_id.blank? || !StandupParticipant.exists?(slack_id: slack_id)

    new(slack_id, name: name)
  end

  def initialize(slack_id, name: nil)
    @slack_id = slack_id
    @name = name
  end

  def name
    @name.presence || participants.first&.slack_name.presence || slack_id
  end

  def participants
    @participants ||= StandupParticipant.includes(standup: :standup_schedule_exceptions).where(slack_id: slack_id).joins(:standup).order("standups.name").to_a
  end

  def participant_for(standup_id)
    participants.find { |participant| participant.standup_id == standup_id.to_i }
  end

  def standups
    participants.map(&:standup)
  end

  def responses
    StandupResponse.includes(:standup).where(slack_id: slack_id, standup_id: participants.map(&:standup_id))
  end

  def away_until
    dates = participants.select(&:active?).filter_map(&:vacation_until).select { |date| date >= Date.current }
    dates.min if dates.any? && dates.size == participants.count(&:active?)
  end
end

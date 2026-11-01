# A person who takes part in standups, identified by their chat platform and
# user ID on it. Members don't have a User record; they sign in with the platform.
class Member
  attr_reader :platform, :platform_user_id

  def self.for(platform, platform_user_id, name: nil)
    return if platform.blank? || platform_user_id.blank? || !ChatPlatform.supported?(platform)
    return unless StandupParticipant.on_platform(platform).exists?(platform_user_id: platform_user_id)

    new(platform, platform_user_id, name: name)
  end

  def initialize(platform, platform_user_id, name: nil)
    @platform = platform.to_s
    @platform_user_id = platform_user_id
    @name = name
  end

  def name
    @name.presence || participants.first&.display_name.presence || platform_user_id
  end

  def avatar_url
    participants.find(&:avatar_url)&.avatar_url
  end

  def participants
    @participants ||= StandupParticipant
      .on_platform(platform)
      .includes(standup: :standup_schedule_exceptions)
      .where(platform_user_id: platform_user_id)
      .order("standups.name")
      .to_a
  end

  def participant_for(standup_id)
    participants.find { |participant| participant.standup_id == standup_id.to_i }
  end

  def standups
    participants.map(&:standup)
  end

  def responses
    StandupResponse.includes(:standup).where(platform_user_id: platform_user_id, standup_id: participants.map(&:standup_id))
  end

  def away_until
    dates = participants.select(&:active?).filter_map(&:vacation_until).select { |date| date >= Date.current }
    dates.min if dates.any? && dates.size == participants.count(&:active?)
  end
end

# A standup participant. The first block of keys is the admin API's contract;
# the rest was added for the console.
class ParticipantSerializer
  def initialize(participant)
    @participant = participant
  end

  def as_json(*)
    {
      id: @participant.id,
      standup_id: @participant.standup_id,
      platform_user_id: @participant.platform_user_id,
      display_name: @participant.display_name,
      active: @participant.active,
      cached_timezone: @participant.cached_timezone,
      created_at: @participant.created_at&.iso8601,
      updated_at: @participant.updated_at&.iso8601,
      avatar_url: @participant.avatar_url,
      vacation_until: @participant.vacation_until&.iso8601,
      timezone_cache_status: @participant.timezone_cache_status,
      timezone_cache_status_description: @participant.timezone_cache_status_description
    }
  end
end

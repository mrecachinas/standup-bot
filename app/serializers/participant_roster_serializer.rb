# A participant as the console's People page shows it: the admin API fields
# plus manager status, availability, and timezone sync state.
class ParticipantRosterSerializer
  def initialize(participant, manager_user_id: nil, manager_count: 0, holiday_today: false, today: Date.current)
    @participant = participant
    @manager_user_id = manager_user_id
    @manager_count = manager_count
    @holiday_today = holiday_today
    @today = today
  end

  def as_json(*)
    status_label = @participant.active? ? "Active" : "Inactive"

    ParticipantSerializer.new(@participant).as_json.merge(
      status_label: status_label,
      status_tone: UiFormat.status_tone(status_label),
      manager: @manager_user_id.present?,
      manager_user_id: @manager_user_id,
      can_make_manager: @manager_user_id.blank?,
      can_remove_manager: @manager_user_id.present? && @manager_count > 1,
      timezone_label: @participant.cached_timezone.presence || "Unknown",
      timezone_synced: @participant.timezone_cache_status == "fresh",
      available_today: @participant.available_on?(@today),
      vacation_status: @participant.vacation_status_on(@today),
      holiday_status: ("Holiday today" if @holiday_today)
    )
  end
end

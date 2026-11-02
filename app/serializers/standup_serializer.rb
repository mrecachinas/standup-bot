# A standup as the API returns it. The first block of keys is the admin API's
# long-standing contract; everything after it was added for the console.
class StandupSerializer
  def initialize(standup, include_counts: false)
    @standup = standup
    @include_counts = include_counts
  end

  def as_json(*)
    payload = {
      id: @standup.id,
      name: @standup.name,
      platform: @standup.platform,
      platform_channel: @standup.platform_channel,
      intro: @standup.intro,
      outro: @standup.outro,
      questions: @standup.questions || [],
      schedule_type: @standup.schedule_type,
      schedule_days: @standup.schedule_days || [],
      default_hour: @standup.default_hour,
      default_minute: @standup.default_minute,
      respect_timezone: @standup.respect_timezone,
      active: @standup.active,
      created_at: @standup.created_at&.iso8601,
      updated_at: @standup.updated_at&.iso8601
    }

    if @include_counts
      payload[:participants_count] = @standup.standup_participants.count
      payload[:active_participants_count] = @standup.standup_participants.active.count
      payload[:responses_count] = @standup.standup_responses.count
    end

    payload.merge(console_fields)
  end

  private

  def console_fields
    {
      platform_label: @standup.chat_platform.label,
      platform_channel_name: @standup.platform_channel_name,
      reminder_enabled: @standup.reminder_enabled,
      reminder_after_minutes: @standup.reminder_after_minutes,
      max_reminders: @standup.max_reminders,
      send_time: UiFormat.format_clock(@standup.default_hour, @standup.default_minute),
      schedule_summary: UiFormat.schedule_summary(@standup),
      schedule_sentence: UiFormat.schedule_sentence(@standup),
      schedule_picker: UiFormat.schedule_picker_state(@standup),
      status_label: status_label,
      status_tone: UiFormat.status_tone(status_label),
      channel_label: @standup.platform_channel_name.presence || @standup.platform_channel.to_s.delete_prefix("#"),
      timezone_label: @standup.respect_timezone? ? "Participant timezones" : "UTC"
    }
  end

  def status_label
    @standup.active? ? "Active" : "Paused"
  end
end

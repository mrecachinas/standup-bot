# A one-off change to a standup's schedule: a skipped, holiday, cancelled, or
# moved run.
class ScheduleExceptionSerializer
  def initialize(schedule_exception)
    @schedule_exception = schedule_exception
  end

  def as_json(*)
    scheduled_at = @schedule_exception.scheduled_at

    {
      id: @schedule_exception.id,
      standup_id: @schedule_exception.standup_id,
      exception_type: @schedule_exception.exception_type,
      label: @schedule_exception.label,
      tone: UiFormat.status_tone(@schedule_exception.label),
      blocks_occurrence: @schedule_exception.blocks_occurrence?,
      original_date: @schedule_exception.original_date&.iso8601,
      original_date_label: @schedule_exception.original_date&.to_fs(:long),
      rescheduled_date: @schedule_exception.rescheduled_date&.iso8601,
      rescheduled_hour: @schedule_exception.rescheduled_hour,
      rescheduled_minute: @schedule_exception.rescheduled_minute,
      rescheduled_time: rescheduled_time,
      rescheduled_timezone: @schedule_exception.rescheduled_timezone,
      scheduled_at: scheduled_at&.iso8601,
      scheduled_at_label: scheduled_at&.strftime("%a, %b %-d at %-l:%M %p %Z"),
      reason: @schedule_exception.reason,
      created_at: @schedule_exception.created_at&.iso8601,
      updated_at: @schedule_exception.updated_at&.iso8601
    }
  end

  private

  def rescheduled_time
    hour = @schedule_exception.rescheduled_hour
    minute = @schedule_exception.rescheduled_minute
    return if hour.nil? || minute.nil?

    format("%02d:%02d", hour, minute)
  end
end

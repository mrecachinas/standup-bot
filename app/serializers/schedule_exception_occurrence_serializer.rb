# One upcoming run of a standup (including skipped and moved ones), with
# times shown in the timezone the schedule page previews.
class ScheduleExceptionOccurrenceSerializer
  TIME_FORMAT = "%A, %B %-d, %Y at %-l:%M %p %Z".freeze

  def initialize(occurrence, timezone:)
    @occurrence = occurrence
    @timezone = timezone
  end

  def as_json(*)
    local = @occurrence.scheduled_at.in_time_zone(@timezone)
    exception = @occurrence.exception

    {
      standup_date: @occurrence.standup_date.iso8601,
      standup_date_label: @occurrence.standup_date.to_fs(:long),
      scheduled_at: @occurrence.scheduled_at.iso8601,
      local_date: local.to_date.iso8601,
      local_time: local.strftime("%H:%M"),
      local_label: local.strftime(TIME_FORMAT),
      local_short_label: local.to_fs(:weekday_month_day),
      status: @occurrence.status.to_s,
      status_label: @occurrence.status_label,
      status_tone: status_tone,
      sendable: @occurrence.sendable?,
      blocked: @occurrence.blocked?,
      note: exception&.reason.presence || ("No prompts will be sent" if @occurrence.blocked?),
      exception_id: exception&.id,
      can_skip: @occurrence.sendable? && exception.nil?,
      can_unskip: exception.present? && exception.skipped_date?
    }
  end

  private

  def status_tone
    return "warning" unless @occurrence.sendable?

    @occurrence.exception ? "info" : "success"
  end
end

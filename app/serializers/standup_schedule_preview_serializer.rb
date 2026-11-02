# The next few runs of a standup's schedule as seen from one timezone, for the
# editor's live preview and the overview's "Upcoming" list. Works for unsaved
# standups too, and explains what to fix when the schedule can't be previewed.
class StandupSchedulePreviewSerializer
  OCCURRENCE_COUNT = 4
  DEFAULT_TIMEZONE = "UTC".freeze
  UNPREVIEWABLE_MESSAGE = "Fix recurrence and send time to preview upcoming occurrences.".freeze
  EMPTY_MESSAGE = "Choose a recurrence and send time to see upcoming runs.".freeze

  attr_reader :error, :occurrences, :zone

  # error: a schedule problem found while reading the form (for example no
  # days picked); it replaces the preview.
  def initialize(standup, timezone: DEFAULT_TIMEZONE, count: OCCURRENCE_COUNT, error: nil)
    @standup = standup
    @zone = Standup.resolve_time_zone(timezone.presence || DEFAULT_TIMEZONE)
    @count = count
    @error = error
    @occurrences = error ? [] : build_occurrences
  end

  def as_json(*)
    {
      occurrences: @occurrences.map { |occurrence| occurrence_json(occurrence) },
      preview_timezone: @zone.name,
      error: @error,
      empty_message: EMPTY_MESSAGE
    }
  end

  def occurrence_json(occurrence)
    local = occurrence.in_time_zone(@zone)
    {
      scheduled_at: occurrence.utc.iso8601,
      date: local.to_date.iso8601,
      weekday: local.strftime("%A"),
      time: local.strftime("%-l:%M %p %Z"),
      label: local.strftime("%A, %B %-d, %Y at %-l:%M %p %Z")
    }
  end

  private

  def build_occurrences
    unless previewable_schedule?
      @error = UNPREVIEWABLE_MESSAGE
      return []
    end

    @standup.upcoming_occurrences_in_timezone(@zone, count: @count)
  rescue StandardError => error
    Rails.logger.debug "Unable to preview standup schedule: #{error.class} - #{error.message}"
    @error = UNPREVIEWABLE_MESSAGE
    []
  end

  def previewable_schedule?
    Standup::SCHEDULE_TYPES.include?(@standup.schedule_type) &&
      integer_in_range?(@standup.default_hour, 0..23) &&
      integer_in_range?(@standup.default_minute, 0..59) &&
      schedule_days_previewable?
  end

  def schedule_days_previewable?
    days = Array(@standup.schedule_days).reject(&:blank?)

    case @standup.schedule_type
    when "custom"
      days.any? && days.all? { |day| integer_in_range?(day, 0..6) }
    when "weekly", "biweekly"
      days.empty? || days.all? { |day| integer_in_range?(day, 0..6) }
    when "monthly"
      days.empty? || days.all? { |day| integer_in_range?(day, 1..31) }
    else
      true
    end
  end

  def integer_in_range?(value, range)
    integer = Integer(value, exception: false)
    integer.present? && range.cover?(integer)
  end
end

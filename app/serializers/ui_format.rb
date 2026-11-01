# Display values the console shows, computed on the server so the browser
# doesn't reimplement scheduling or status rules.
module UiFormat
  WEEKDAY_ABBREVIATIONS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
  WEEKDAY_NUMBERS = [ 1, 2, 3, 4, 5 ].freeze

  module_function

  def schedule_summary(standup)
    days = schedule_day_numbers(standup)
    day_names = days.sort.filter_map { |day| WEEKDAY_ABBREVIATIONS[day] }
    base = case standup.schedule_type
    when "daily" then "Every day"
    when "weekdays" then "Weekdays"
    when "weekly" then day_names.any? ? "Weekly on #{day_names.to_sentence}" : "Weekly"
    when "biweekly" then day_names.any? ? "Every 2 weeks on #{day_names.to_sentence}" : "Every 2 weeks"
    when "monthly" then "Monthly on day #{days.first || 1}"
    when "custom" then day_names.any? ? day_names.join(", ") : "Custom"
    else standup.schedule_type.to_s.titleize
    end
    "#{base} at #{format_clock(standup.default_hour, standup.default_minute)}"
  end

  def schedule_sentence(standup)
    "#{schedule_summary(standup)}, #{standup.respect_timezone? ? "in each person's local time" : "UTC"}"
  end

  # How the editor's day picker should start for an existing schedule.
  def schedule_picker_state(standup)
    days = schedule_day_numbers(standup)
    case standup.schedule_type
    when "daily" then { frequency: "weekly", days: (0..6).to_a }
    when "weekdays" then { frequency: "weekly", days: WEEKDAY_NUMBERS }
    when "biweekly" then { frequency: "biweekly", days: days.first(1).presence || [ 1 ] }
    when "monthly" then { frequency: "monthly", days: WEEKDAY_NUMBERS, monthly_day: days.first || 1 }
    # The scheduler only uses the first day of a weekly schedule (Monday if none).
    when "weekly" then { frequency: "weekly", days: days.first(1).presence || [ 1 ] }
    else { frequency: "weekly", days: days }
    end
  end

  def format_clock(hour, minute)
    return "—" if hour.nil? || minute.nil?

    Time.utc(2000, 1, 1, hour, minute).strftime("%-l:%M %p")
  end

  def rate_tone(rate)
    return "danger" if rate.to_f < 50
    return "warning" if rate.to_f < 75

    "success"
  end

  # success, info, warning, danger, or nil for a neutral badge.
  def status_tone(label)
    case label.to_s.downcase
    when "completed", "answered", "succeeded", "scheduled", "ok", "active", "configured", "healthy" then "success"
    when "pending", "queued", "running", "rescheduled" then "info"
    when "missed", "expired", "paused", "warn", "degraded", "needs setup", "skipped", "skipped date", "holiday", "cancelled", "canceled" then "warning"
    when "failed", "error", "unhealthy" then "danger"
    end
  end

  def schedule_day_numbers(standup)
    Array(standup.schedule_days).filter_map { |day| Integer(day, exception: false) }
  end
end

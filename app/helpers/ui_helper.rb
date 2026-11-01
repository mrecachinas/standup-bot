module UiHelper
  ICONS = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    chart: '<path d="M3 3v18h18"/><path d="M8 17V11"/><path d="M13 17V7"/><path d="M18 17v-4"/>',
    inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4"/><path d="M8 2v4"/><path d="M3 10h18"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M16 13H8"/><path d="M16 17H8"/>',
    hash: '<path d="M4 9h16"/><path d="M4 15h16"/><path d="M10 3 8 21"/><path d="M16 3l-2 18"/>',
    settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
    plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
    pause: '<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>',
    play: '<path d="m6 3 14 9-14 9V3z"/>',
    more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    check_circle: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    x_circle: '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    globe: '<circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>',
    repeat: '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
    trash: '<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m17 8-5-5-5 5"/><path d="M12 3v12"/>',
    refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
    send: '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
    message: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4 3 9 3s9-1.34 9-3"/>',
    layers: '<path d="m12 2 10 5-10 5L2 7l10-5z"/><path d="m2 17 10 5 10-5"/><path d="m2 12 10 5 10-5"/>',
    activity: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    logo: '<path d="M4 6h10"/><path d="M4 12h16"/><path d="M4 18h7"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    monitor: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>'
  }.freeze

  AVATAR_PALETTE = [
    %w[#e0e7ff #3730a3], %w[#dcfce7 #166534], %w[#fef3c7 #92400e], %w[#fce7f3 #9d174d],
    %w[#e0f2fe #075985], %w[#ede9fe #5b21b6], %w[#ffedd5 #9a3412], %w[#ccfbf1 #115e59]
  ].freeze

  WEEKDAY_ABBREVIATIONS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  def icon(name, css_class: nil)
    tag.svg(ICONS.fetch(name.to_sym).html_safe, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none",
      stroke: "currentColor", "stroke-width": 1.75, "stroke-linecap": "round", "stroke-linejoin": "round",
      class: [ "icon", css_class ].compact_blank.join(" "), "aria-hidden": "true")
  end

  def initials_for(name)
    words = name.to_s.scan(/[[:alnum:]]+/)
    return "?" if words.empty?

    (words.size == 1 ? words.first[0, 2] : words.first[0] + words.last[0]).upcase
  end

  # Slack photo when we have one, with initials underneath as the fallback.
  def avatar(name, size: nil, url: nil)
    background, foreground = AVATAR_PALETTE[name.to_s.sum % AVATAR_PALETTE.size]
    photo = SlackAvatar.safe_url?(url) ? tag.img(src: url, alt: "", class: "avatar-img", loading: "lazy", referrerpolicy: "no-referrer") : "".html_safe
    tag.span(class: [ "avatar", size && "avatar-#{size}" ].compact_blank.join(" "),
      style: "--avatar-bg:#{background};--avatar-fg:#{foreground}", title: name, "aria-hidden": "true") do
      safe_join([ initials_for(name), photo ])
    end
  end

  # people: names, or [name, avatar_url] pairs.
  def avatar_stack(people, limit: 5)
    people = Array(people).map { |person| Array(person) }
    names = people.map(&:first)
    tag.span(class: "avatar-stack", title: names.to_sentence) do
      safe_join(people.first(limit).map { |name, url| avatar(name, size: "sm", url: url) }) +
        (people.size > limit ? tag.span("+#{people.size - limit}", class: "avatar-more") : "".html_safe)
    end
  end

  def standup_status_badge(standup)
    standup.active? ? status_badge("Active", "success") : status_badge("Paused", "warning")
  end

  def status_badge(label, tone = nil)
    tone ||= case label.to_s.downcase
    when "completed", "answered", "succeeded", "scheduled", "ok", "active", "configured", "healthy" then "success"
    when "pending", "queued", "running", "rescheduled" then "info"
    when "missed", "expired", "paused", "warn", "degraded", "needs setup", "skipped", "skipped date", "holiday", "cancelled", "canceled" then "warning"
    when "failed", "error", "unhealthy" then "danger"
    end
    tag.span(label, class: [ "badge", tone && "badge-#{tone}" ].compact_blank.join(" "))
  end

  def schedule_summary(standup)
    days = Array(standup.schedule_days).filter_map { |day| Integer(day, exception: false) }
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

  def format_clock(hour, minute)
    return "—" if hour.nil? || minute.nil?

    Time.utc(2000, 1, 1, hour, minute).strftime("%-l:%M %p")
  end

  def percent(value)
    return "—" if value.nil?

    "#{number_with_precision(value, precision: 0)}%"
  end

  def rate_tone(rate)
    return "danger" if rate.to_f < 50
    return "warning" if rate.to_f < 75

    "success"
  end

  def progress_bar(rate, tone: nil)
    tag.span(class: [ "progress", tone && "progress-#{tone}" ].compact_blank.join(" "), role: "presentation") do
      tag.span(style: "width: #{rate.to_f.clamp(0, 100)}%")
    end
  end

  def delta_badge(current, previous, suffix: " pts")
    return if current.nil? || previous.nil?

    diff = (current.to_f - previous.to_f).round
    css = if diff.zero? then "delta-flat" elsif diff.positive? then "delta-up" else "delta-down" end
    arrow = if diff.zero? then "" elsif diff.positive? then "↑ " else "↓ " end
    tag.span("#{arrow}#{diff.abs}#{suffix}", class: "delta #{css}", title: "Compared with the previous period")
  end

  def date_tile(date, blocked: false)
    tag.span(class: [ "date-tile", blocked && "is-blocked" ].compact_blank.join(" "), "aria-hidden": "true") do
      tag.span(date.strftime("%b"), class: "date-tile-month") + tag.span(date.day, class: "date-tile-day")
    end
  end

  def nav_link(label, path, icon_name:, active: false, **options)
    link_to path, class: [ "nav-item", active && "is-active" ].compact_blank.join(" "), "aria-current": (active ? "page" : nil), **options do
      icon(icon_name) + tag.span(label, class: "truncate")
    end
  end

  def relative_time(time)
    return "—" if time.blank?

    label = time.future? ? "in #{time_ago_in_words(time)}" : "#{time_ago_in_words(time)} ago"
    tag.time(label, datetime: time.iso8601, title: time.to_fs(:long))
  end
end

# Named formats for dates and times shown in the console and in chat. Use them
# with to_fs, e.g. date.to_fs(:month_day).
{
  month_day: "%b %-d",                   # Apr 7
  month_day_year: "%b %-d, %Y",          # Apr 7, 2025
  weekday_month_day: "%A, %B %-d",       # Monday, April 7
  short_weekday_month_day: "%a, %b %-d"  # Mon, Apr 7
}.each do |name, format|
  Date::DATE_FORMATS[name] = format
  Time::DATE_FORMATS[name] = format
end

Time::DATE_FORMATS[:clock_with_zone] = "%-l:%M %p %Z"                      # 9:00 AM EDT
Time::DATE_FORMATS[:short_weekday_clock] = "%a, %b %-d at %-l:%M %p %Z"    # Mon, Apr 7 at 9:00 AM EDT

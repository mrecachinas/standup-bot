# A start/end date pair taken from request params. Unparseable dates fall back
# to the defaults, a reversed range is swapped, and a range longer than
# max_days keeps its most recent days (and reports that it was limited).
ReportingRange = Data.define(:start_date, :end_date, :limited) do
  def self.from_params(start_date:, end_date:, default_end:, default_start:, max_days:)
    finish = parse_date(end_date) || default_end
    start = parse_date(start_date) || default_start.call(finish)
    start, finish = finish, start if start > finish

    limited = (finish - start).to_i >= max_days
    start = finish - (max_days - 1) if limited

    new(start_date: start, end_date: finish, limited: limited)
  end

  def self.parse_date(value)
    return if value.blank?
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def limited?
    limited
  end
end

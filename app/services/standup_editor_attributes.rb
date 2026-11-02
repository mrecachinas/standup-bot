# Maps the console editor's schedule and question fields (a day picker, a send
# time, one question per row) onto the standup's columns. Requests that don't
# send any of these fields, like scripts using the admin token, pass through
# untouched.
class StandupEditorAttributes
  WEEKDAY_NUMBERS = [ 1, 2, 3, 4, 5 ].freeze
  FIELDS = %w[frequency days monthly_day send_time question_rows questions_text schedule_days_text].freeze

  attr_reader :attributes, :schedule_error

  def initialize(attributes)
    @attributes = attributes.to_h.stringify_keys
    convert! if @attributes.keys.intersect?(FIELDS)
  end

  private

  def convert!
    apply_day_picker! if attributes.key?("frequency")

    if attributes.key?("question_rows") || attributes.key?("questions_text") || attributes.key?("questions")
      attributes["questions"] = questions
    end
    if attributes.key?("schedule_type") || attributes.key?("schedule_days") || attributes.key?("schedule_days_text") || attributes.key?("monthly_day")
      attributes["schedule_days"] = schedule_days
    end
    apply_send_time!

    @attributes = attributes.except("question_rows", "questions_text", "schedule_days_text", "monthly_day", "days")
  end

  # The editor picks days and a repeat interval; turn that into the schedule
  # type the scheduler understands. "weekly" and "biweekly" only support a
  # single day, so several days become "custom".
  def apply_day_picker!
    frequency = attributes.delete("frequency").to_s
    days = Array(attributes.delete("days")).filter_map { |day| Integer(day, exception: false) }.select { |day| (0..6).cover?(day) }.uniq.sort

    case frequency
    when "monthly"
      attributes["schedule_type"] = "monthly"
    when "biweekly"
      attributes["schedule_type"] = "biweekly"
      attributes["schedule_days"] = days
      @schedule_error = "Every other week runs on one day. Pick a single day." unless days.size == 1
    else
      attributes["schedule_type"], attributes["schedule_days"] =
        if days.size == 7 then [ "daily", [] ]
        elsif days == WEEKDAY_NUMBERS then [ "weekdays", [] ]
        elsif days.size == 1 then [ "weekly", days ]
        else [ "custom", days ]
        end
      @schedule_error = "Pick at least one day." if days.empty?
    end
  end

  def questions
    if attributes.key?("question_rows")
      split_lines(Array(attributes["question_rows"]).join("\n"))
    elsif attributes.key?("questions_text")
      split_lines(attributes["questions_text"])
    else
      split_lines(Array(attributes["questions"]).join("\n"))
    end
  end

  def schedule_days
    if attributes["schedule_type"] == "monthly"
      Array(attributes["monthly_day"].presence || attributes["schedule_days"]).flatten.reject(&:blank?).first(1)
    elsif attributes.key?("schedule_days_text")
      attributes["schedule_days_text"].to_s.split(/[,\s]+/).reject(&:blank?)
    else
      Array(attributes["schedule_days"]).reject(&:blank?)
    end
  end

  def apply_send_time!
    return unless attributes.key?("send_time")

    send_time = attributes.delete("send_time").to_s
    if send_time.match?(/\A\d{1,2}:\d{2}\z/)
      attributes["default_hour"], attributes["default_minute"] = send_time.split(":").map(&:to_i)
    else
      attributes["default_hour"] = nil
      attributes["default_minute"] = nil
    end
  end

  def split_lines(value)
    value.to_s.lines.map(&:strip).reject(&:blank?)
  end
end

require "erb"
require "json"
require "yaml"

class Standup < ApplicationRecord
  SCHEDULE_TYPES = %w[daily weekdays weekly biweekly monthly custom].freeze
  BIWEEKLY_REFERENCE_DATE = Date.new(2024, 1, 1)
  HOLIDAYS_CONFIG_PATH = Rails.root.join("config/holidays.yml")

  has_many :standup_participants, dependent: :destroy
  has_many :standup_responses, dependent: :destroy

  attribute :intro, :text, default: "Good morning! Time for standup. When you're ready, please answer the following"
  attribute :outro, :text, default: "Thanks for your answers! Have a great day!"
  attribute :questions, :json, default: -> { [] }
  attribute :schedule_days, :json, default: -> { [] }
  attribute :reminder_enabled, :boolean, default: true
  attribute :reminder_after_minutes, :integer, default: 120
  attribute :max_reminders, :integer, default: 1

  validates :name, presence: true
  validates :slack_channel, presence: true
  validates :questions, presence: true
  validates :schedule_type, inclusion: { in: SCHEDULE_TYPES }
  validates :respect_timezone, inclusion: { in: [ true, false ] }
  validates :default_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :default_minute, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 59 }
  validates :reminder_after_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :max_reminders, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :schedule_days_are_valid

  # For custom schedules, store as array of weekday numbers (0=Sunday, 6=Saturday)
  # For weekly, store day of week (0-6)
  # For biweekly, store day of week (0-6); for monthly, store day of month (1-31)

  scope :active, -> { where(active: true) }

  # Calculate the next occurrence of this standup in the given timezone
  def next_occurrence_in_timezone(timezone)
    zone = self.class.resolve_time_zone(timezone)
    now = zone.now

    case schedule_type
    when "daily"
      next_daily_occurrence(now, zone)
    when "weekdays"
      next_weekday_occurrence(now, zone, (1..5).to_a)
    when "weekly"
      next_weekday_occurrence(now, zone, [ configured_weekday ])
    when "biweekly"
      next_biweekly_occurrence(now, zone, configured_weekday)
    when "monthly"
      next_monthly_occurrence(now, zone, configured_month_day)
    when "custom"
      next_weekday_occurrence(now, zone, configured_weekdays)
    else
      raise ArgumentError, "Unsupported schedule_type: #{schedule_type}"
    end
  end

  def holiday_on?(date)
    self.class.holiday_on?(date, self)
  end

  class << self
    def resolve_time_zone(timezone)
      return timezone if timezone.is_a?(ActiveSupport::TimeZone)
      return Time.find_zone(timezone.name) || Time.find_zone!("UTC") if timezone.is_a?(TZInfo::Timezone)

      Time.find_zone(timezone.presence || "UTC") || Time.find_zone!("UTC")
    rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
      Time.find_zone!("UTC")
    end

    def holiday_on?(date, standup = nil)
      holiday_date = normalize_date(date)

      holiday_entries.any? do |entry|
        entry_holiday_date(entry) == holiday_date && holiday_applies_to_standup?(entry, standup)
      end
    end

    def reload_holidays!
      @holiday_entries = nil
    end

    private

    def holiday_entries
      @holiday_entries ||= begin
        if File.exist?(HOLIDAYS_CONFIG_PATH)
          config = YAML.safe_load(
            ERB.new(File.read(HOLIDAYS_CONFIG_PATH)).result,
            aliases: true,
            permitted_classes: [ Date ]
          ) || {}

          entries_for(config["default"]) + entries_for(config[Rails.env])
        else
          []
        end
      rescue Psych::SyntaxError, Errno::ENOENT => error
        Rails.logger.warn "Unable to load holidays config: #{error.class} - #{error.message}"
        []
      end
    end

    def entries_for(value)
      value = value["holidays"] if value.is_a?(Hash) && value.key?("holidays")

      case value
      when nil
        []
      when Array
        value
      else
        [ value ]
      end
    end

    def entry_holiday_date(entry)
      case entry
      when Hash
        normalize_date(entry["date"] || entry[:date])
      else
        normalize_date(entry)
      end
    rescue ArgumentError
      nil
    end

    def holiday_applies_to_standup?(entry, standup)
      return true unless entry.is_a?(Hash)

      standup_identifier = entry["standup_id"] || entry[:standup_id] ||
        entry["standup"] || entry[:standup] ||
        entry["slack_channel"] || entry[:slack_channel]
      return true if standup_identifier.blank? || standup.blank?

      [ standup.id.to_s, standup.name, standup.slack_channel ].include?(standup_identifier.to_s)
    end

    def normalize_date(date)
      return date.to_date if date.respond_to?(:to_date)

      Date.iso8601(date.to_s)
    end
  end

  private

  def next_daily_occurrence(now, zone)
    candidate = scheduled_time_on(zone, now.to_date)
    candidate < now ? scheduled_time_on(zone, now.to_date + 1.day) : candidate
  end

  def next_weekday_occurrence(now, zone, weekdays)
    date = now.to_date

    14.times do
      if weekdays.include?(date.wday)
        candidate = scheduled_time_on(zone, date)
        return candidate if candidate >= now
      end

      date += 1.day
    end

    raise ArgumentError, "Unable to calculate next #{schedule_type} occurrence"
  end

  def next_biweekly_occurrence(now, zone, weekday)
    date = now.to_date

    28.times do
      if date.wday == weekday && biweekly_week?(date)
        candidate = scheduled_time_on(zone, date)
        return candidate if candidate >= now
      end

      date += 1.day
    end

    raise ArgumentError, "Unable to calculate next biweekly occurrence"
  end

  def next_monthly_occurrence(now, zone, day_of_month)
    month_start = now.to_date.beginning_of_month
    candidate = scheduled_time_on(zone, date_for_month_day(month_start, day_of_month))
    return candidate if candidate >= now

    scheduled_time_on(zone, date_for_month_day(month_start.next_month, day_of_month))
  end

  def scheduled_time_on(zone, date)
    zone.local(date.year, date.month, date.day, default_hour, default_minute)
  end

  def date_for_month_day(month_start, day_of_month)
    Date.new(month_start.year, month_start.month, [ day_of_month, month_start.end_of_month.day ].min)
  end

  def biweekly_week?(date)
    week_start = date.beginning_of_week(:monday)
    ((week_start - BIWEEKLY_REFERENCE_DATE) / 7).to_i.even?
  end

  def configured_weekday
    normalized_schedule_days.first || 1
  end

  def configured_weekdays
    normalized_schedule_days.presence || [ 1 ]
  end

  def configured_month_day
    normalized_schedule_days.first || 1
  end

  def normalized_schedule_days
    Array(schedule_days).filter_map { |day| Integer(day, exception: false) }
  end

  def schedule_days_are_valid
    days = Array(schedule_days).reject(&:blank?)
    if schedule_type == "custom" && days.empty?
      errors.add(:schedule_days, "must include at least one weekday for custom schedule")
      return
    end

    return if days.empty?

    range = schedule_type == "monthly" ? (1..31) : (0..6)
    invalid_days = days.reject do |day|
      integer_day = Integer(day, exception: false)
      integer_day.present? && range.cover?(integer_day)
    end

    errors.add(:schedule_days, "contains invalid days for #{schedule_type} schedule") if invalid_days.any?
  end
end

require "erb"
require "json"
require "yaml"

class Standup < ApplicationRecord
  SCHEDULE_TYPES = %w[daily weekdays weekly biweekly monthly custom].freeze
  BIWEEKLY_REFERENCE_DATE = Date.new(2024, 1, 1)
  HOLIDAYS_CONFIG_PATH = Rails.root.join("config/holidays.yml")
  SLACK_CHANNEL_PATTERN = /\A#?[A-Za-z0-9][A-Za-z0-9_-]*\z/
  SCHEDULE_EXCEPTION_LOOKBACK_DAYS = 400
  SCHEDULE_EXCEPTION_LOOKAHEAD_DAYS = 400

  Occurrence = Struct.new(:standup_date, :scheduled_at, :status, :exception, keyword_init: true) do
    def sendable?
      %w[scheduled rescheduled].include?(status.to_s)
    end

    def blocked?
      !sendable?
    end

    def status_label
      status.to_s.tr("_", " ").titleize
    end
  end

  has_many :standup_participants, dependent: :destroy
  has_many :standup_responses, dependent: :destroy
  has_many :standup_ownerships, dependent: :destroy
  has_many :standup_schedule_exceptions, dependent: :destroy
  has_many :owners, through: :standup_ownerships, source: :user
  has_one :report_configuration, dependent: :destroy
  has_many :report_generations, dependent: :destroy

  attribute :intro, :text, default: "Good morning! Time for standup. When you're ready, please answer the following"
  attribute :outro, :text, default: "Thanks for your answers! Have a great day!"
  attribute :questions, :json, default: -> { [] }
  attribute :schedule_days, :json, default: -> { [] }
  attribute :reminder_enabled, :boolean, default: true
  attribute :reminder_after_minutes, :integer, default: 120
  attribute :max_reminders, :integer, default: 1

  before_validation :normalize_slack_channel
  before_validation :normalize_questions
  before_validation :normalize_schedule_days

  validates :name, presence: true
  validates :slack_channel, presence: true
  validates :slack_channel,
    format: { with: SLACK_CHANNEL_PATTERN, message: "must be a Slack channel name or ID without spaces" },
    allow_blank: true
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

  def self.manageable_by(user)
    return none unless user&.active?
    return all if user.admin?

    joins(:standup_ownerships).where(standup_ownerships: { user_id: user.id }).distinct
  end

  def manageable_by?(user)
    user&.can_manage_standup?(self) || false
  end

  def upcoming_occurrences_in_timezone(timezone, count: 5, from: nil)
    upcoming_occurrence_details_in_timezone(timezone, count: count, from: from).map(&:scheduled_at)
  end

  def upcoming_occurrence_details_in_timezone(timezone, count: 5, from: nil, include_blocked: false)
    zone = self.class.resolve_time_zone(timezone)
    cursor = (from || zone.now).in_time_zone(zone)
    start_date = cursor.to_date - SCHEDULE_EXCEPTION_LOOKBACK_DAYS
    end_date = cursor.to_date + SCHEDULE_EXCEPTION_LOOKAHEAD_DAYS
    exceptions_by_date = standup_schedule_exceptions
      .where(original_date: start_date..end_date)
      .index_by(&:original_date)
    occurrences = []
    date = start_date

    (SCHEDULE_EXCEPTION_LOOKBACK_DAYS + SCHEDULE_EXCEPTION_LOOKAHEAD_DAYS + 1).times do
      if base_scheduled_on_date?(date)
        occurrence = occurrence_for_date(zone, date, exceptions_by_date[date])
        if occurrence.scheduled_at.present? && occurrence.scheduled_at >= cursor && (include_blocked || occurrence.sendable?)
          occurrences << occurrence
        end
      end

      date += 1.day
    end

    occurrences
      .sort_by { |occurrence| [ occurrence.scheduled_at, occurrence.standup_date ] }
      .first(count)
  end

  # Calculate the next occurrence of this standup in the given timezone
  def next_occurrence_in_timezone(timezone)
    next_occurrence_detail_in_timezone(timezone)&.scheduled_at
  end

  def next_occurrence_detail_in_timezone(timezone, from: nil)
    upcoming_occurrence_details_in_timezone(timezone, count: 1, from: from).first
  end

  def scheduled_on_date?(date, include_exceptions: true)
    scheduled_date = normalize_schedule_date(date)
    return false unless base_scheduled_on_date?(scheduled_date)
    return true unless include_exceptions

    !skips_occurrence_on?(scheduled_date)
  end

  def scheduled_without_exceptions_on_date?(date)
    scheduled_on_date?(date, include_exceptions: false)
  end

  def holiday_on?(date)
    schedule_exception_on(date)&.holiday? || self.class.holiday_on?(date, self)
  end

  def skips_occurrence_on?(date)
    exception = schedule_exception_on(date)
    return exception.blocks_occurrence? if exception

    self.class.holiday_on?(date, self)
  end

  def schedule_exception_on(date)
    scheduled_date = normalize_schedule_date(date)
    if standup_schedule_exceptions.loaded?
      standup_schedule_exceptions.find { |exception| exception.original_date == scheduled_date }
    else
      standup_schedule_exceptions.find_by(original_date: scheduled_date)
    end
  end

  def occurrence_for_date(zone, date, exception = nil)
    exception ||= schedule_exception_on(date)

    if exception&.rescheduled?
      Occurrence.new(
        standup_date: date,
        scheduled_at: exception.scheduled_at,
        status: "rescheduled",
        exception: exception
      )
    elsif exception&.cancelled?
      occurrence_with_status(zone, date, "cancelled", exception)
    elsif exception&.skipped_date?
      occurrence_with_status(zone, date, "skipped", exception)
    elsif exception&.holiday? || self.class.holiday_on?(date, self)
      occurrence_with_status(zone, date, "holiday", exception)
    else
      occurrence_with_status(zone, date, "scheduled", exception)
    end
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

  def base_scheduled_on_date?(date)
    case schedule_type
    when "daily"
      true
    when "weekdays"
      date.on_weekday?
    when "weekly"
      date.wday == configured_weekday
    when "biweekly"
      date.wday == configured_weekday && biweekly_week?(date)
    when "monthly"
      date.day == [ configured_month_day, date.end_of_month.day ].min
    when "custom"
      configured_weekdays.include?(date.wday)
    else
      false
    end
  end

  def occurrence_with_status(zone, date, status, exception)
    Occurrence.new(
      standup_date: date,
      scheduled_at: scheduled_time_on(zone, date),
      status: status,
      exception: exception
    )
  end

  def normalize_schedule_date(date)
    return date.to_date if date.respond_to?(:to_date)

    Date.iso8601(date.to_s)
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

  def normalize_slack_channel
    self.slack_channel = slack_channel.to_s.strip.sub(/\A#/, "") if slack_channel.present?
  end

  def normalize_questions
    self.questions = Array(questions).map { |question| question.to_s.strip }.reject(&:blank?)
  end

  def normalize_schedule_days
    self.schedule_days = Array(schedule_days).reject(&:blank?).map do |day|
      Integer(day, exception: false) || day
    end
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

class StandupScheduleException < ApplicationRecord
  TYPES = %w[skipped_date holiday cancelled rescheduled].freeze
  BLOCKING_TYPES = %w[skipped_date holiday cancelled].freeze
  RESCHEDULED_TIME_PATTERN = /\A\d{1,2}:\d{2}\z/

  belongs_to :standup

  attr_accessor :rescheduled_time

  before_validation :normalize_reason
  before_validation :apply_rescheduled_time

  validates :exception_type, inclusion: { in: TYPES }
  validates :original_date, presence: true, uniqueness: { scope: :standup_id }
  validates :rescheduled_hour,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 },
    allow_nil: true
  validates :rescheduled_minute,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 59 },
    allow_nil: true
  validate :original_date_matches_schedule
  validate :reschedule_fields_are_valid

  scope :upcoming_first, -> { order(:original_date, :created_at) }

  def skipped_date?
    exception_type == "skipped_date"
  end

  def holiday?
    exception_type == "holiday"
  end

  def cancelled?
    exception_type == "cancelled"
  end

  def rescheduled?
    exception_type == "rescheduled"
  end

  def blocks_occurrence?
    BLOCKING_TYPES.include?(exception_type)
  end

  def scheduled_at
    return unless rescheduled?
    return if rescheduled_date.blank? || rescheduled_hour.blank? || rescheduled_minute.blank? || rescheduled_timezone.blank?

    zone = Time.find_zone(rescheduled_timezone)
    zone&.local(rescheduled_date.year, rescheduled_date.month, rescheduled_date.day, rescheduled_hour, rescheduled_minute)
  end

  def label
    case exception_type
    when "skipped_date"
      "Skipped date"
    when "holiday"
      "Holiday"
    when "cancelled"
      "Cancelled"
    when "rescheduled"
      "Rescheduled"
    else
      exception_type.to_s.titleize
    end
  end

  private

  def normalize_reason
    self.reason = reason.to_s.strip.presence
    self.rescheduled_timezone = rescheduled_timezone.to_s.strip.presence
  end

  def apply_rescheduled_time
    return if rescheduled_time.blank?
    return unless rescheduled_time.to_s.match?(RESCHEDULED_TIME_PATTERN)

    hour, minute = rescheduled_time.split(":").map(&:to_i)
    self.rescheduled_hour = hour
    self.rescheduled_minute = minute
  end

  def original_date_matches_schedule
    return if original_date.blank? || standup.blank?
    return if standup.scheduled_without_exceptions_on_date?(original_date)

    errors.add(:original_date, "must be a scheduled date for this standup")
  end

  def reschedule_fields_are_valid
    if rescheduled?
      validate_rescheduled_date
      validate_rescheduled_time
      validate_rescheduled_timezone
    elsif rescheduled_date.present? || rescheduled_hour.present? || rescheduled_minute.present? || rescheduled_timezone.present?
      errors.add(:base, "Reschedule details are only allowed for rescheduled exceptions")
    end
  end

  def validate_rescheduled_date
    errors.add(:rescheduled_date, "can't be blank") if rescheduled_date.blank?
  end

  def validate_rescheduled_time
    if rescheduled_time.present? && !rescheduled_time.to_s.match?(RESCHEDULED_TIME_PATTERN)
      errors.add(:rescheduled_time, "is not valid")
      return
    end

    if rescheduled_hour.blank? || rescheduled_minute.blank?
      errors.add(:rescheduled_time, "can't be blank")
    elsif !rescheduled_hour.to_i.between?(0, 23) || !rescheduled_minute.to_i.between?(0, 59)
      errors.add(:rescheduled_time, "is not valid")
    end
  end

  def validate_rescheduled_timezone
    if rescheduled_timezone.blank?
      errors.add(:rescheduled_timezone, "can't be blank")
    elsif !StandupParticipant.valid_timezone?(rescheduled_timezone)
      errors.add(:rescheduled_timezone, "is not valid")
    end
  end
end

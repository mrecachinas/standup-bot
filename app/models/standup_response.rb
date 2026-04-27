require "json"

class StandupResponse < ApplicationRecord
  STATUSES = %w[pending completed skipped cancelled expired].freeze
  MAX_ANSWER_LENGTH = 10_000

  belongs_to :standup

  attribute :answers, :json, default: -> { [] }
  attribute :reminder_count, :integer, default: 0

  before_validation :set_default_standup_date, on: :create

  validates :slack_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :answers_length_valid

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :skipped, -> { where(status: "skipped") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :expired, -> { where(status: "expired") }
  scope :for_standup_date, ->(date, timezone = Time.zone) { for_date_in_timezone(date, timezone) }
  scope :for_date_in_timezone, ->(date, timezone) {
    standup_date = normalize_date(date)
    zone = Standup.resolve_time_zone(timezone)
    day_start = zone.local(standup_date.year, standup_date.month, standup_date.day)
    day_range = day_start...(day_start + 1.day)

    where(standup_date: standup_date).or(where(standup_date: nil, created_at: day_range))
  }
  scope :for_today_in_timezone, ->(timezone) {
    zone = Standup.resolve_time_zone(timezone)
    for_date_in_timezone(zone.today, zone)
  }
  scope :for_today, -> { for_today_in_timezone(Time.zone) }
  scope :authorized_for_slack_user, ->(slack_id) {
    joins(standup: :standup_participants)
      .where(slack_id: slack_id)
      .where(standup_participants: { slack_id: slack_id })
      .distinct
  }

  def participant
    standup.standup_participants.find_by(slack_id: slack_id)
  end

  def self.normalize_date(date)
    return date.to_date if date.respond_to?(:to_date)

    Date.iso8601(date.to_s)
  end

  private

  def set_default_standup_date
    self.standup_date ||= (created_at || Time.current).in_time_zone(Time.zone).to_date
  end

  def answers_length_valid
    Array(answers).each_with_index do |answer, index|
      answer_text = answer.respond_to?(:[]) ? (answer["answer"] || answer[:answer]) : answer
      next if answer_text.to_s.length <= MAX_ANSWER_LENGTH

      errors.add(:answers, "answer #{index + 1} exceeds maximum length of #{MAX_ANSWER_LENGTH} characters")
    end
  end
end

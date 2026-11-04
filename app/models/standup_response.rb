require "json"

class StandupResponse < ApplicationRecord
  STATUSES = %w[pending completed skipped cancelled expired].freeze
  MAX_ANSWER_LENGTH = 10_000

  belongs_to :standup

  attribute :answers, :json, default: -> { [] }
  attribute :reminder_count, :integer, default: 0

  before_validation :set_default_standup_date, on: :create

  validates :platform_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :answers_length_valid

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :for_standup_date, ->(date) { where(standup_date: normalize_date(date)) }
  scope :on_platform, ->(platform) { joins(:standup).where(standups: { platform: platform.to_s }) }
  # Responses belonging to this person in standups they're still part of. A
  # subquery rather than a join + DISTINCT, because PostgreSQL can't compare
  # json columns (answers) for DISTINCT.
  scope :authorized_for, ->(platform, platform_user_id) {
    joins(:standup)
      .where(standups: { platform: platform.to_s })
      .where(platform_user_id: platform_user_id)
      .where(standup_id: StandupParticipant.where(platform_user_id: platform_user_id).select(:standup_id))
  }

  # The answer a DM reply should go to: this person's most recent unfinished standup.
  def self.latest_pending_for(platform, platform_user_id)
    authorized_for(platform, platform_user_id).pending.order("standup_responses.created_at DESC").first
  end

  # Edits are only matched against this person's recent responses, newest
  # first. Plenty for real edits, and it keeps the lookup in Ruby so it works
  # the same on MySQL and PostgreSQL.
  EDIT_LOOKBACK = 60.days
  EDIT_LOOKBACK_LIMIT = 100

  def self.editable_for(platform, platform_user_id)
    authorized_for(platform, platform_user_id)
      .where(updated_at: EDIT_LOOKBACK.ago..)
      .order("standup_responses.created_at DESC")
      .limit(EDIT_LOOKBACK_LIMIT)
  end

  # The response and answer index recorded from message_id, in any state.
  def self.find_answer_for_message(platform, platform_user_id, message_id)
    return if message_id.blank?

    editable_for(platform, platform_user_id).each do |response|
      index = response.answer_index_for_message(message_id)
      return [ response, index ] if index
    end

    nil
  end

  def answer_index_for_message(message_id)
    Array(answers).index { |answer| answer["message_id"].present? && answer["message_id"] == message_id.to_s }
  end

  def participant
    standup.standup_participants.find_by(platform_user_id: platform_user_id)
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

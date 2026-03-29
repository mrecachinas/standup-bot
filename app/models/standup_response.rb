require "json"

class StandupResponse < ApplicationRecord
  belongs_to :standup

  attribute :answers, :json, default: -> { [] }

  validates :slack_id, presence: true
  validates :status, inclusion: { in: %w[pending completed skipped cancelled] }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :skipped, -> { where(status: "skipped") }
  scope :for_today, -> { where(created_at: Time.zone.today.all_day) }

  def participant
    standup.standup_participants.find_by(slack_id: slack_id)
  end
end

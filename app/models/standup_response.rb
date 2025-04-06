require "json"

class StandupResponse < ApplicationRecord
  belongs_to :standup

  validates :slack_id, presence: true
  validates :status, inclusion: { in: %w[pending completed skipped] }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :for_today, -> { where("DATE(created_at) = ?", Time.zone.today) }

  def participant
    standup.standup_participants.find_by(slack_id: slack_id)
  end
end

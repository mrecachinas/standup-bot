class StandupResponse < ApplicationRecord
  belongs_to :standup

  validates :slack_id, presence: true
  validates :status, inclusion: { in: %w[pending completed skipped] }

  # Store answers as array of hashes in JSON
  # [{ question: "...", answer: "...", timestamp: "..." }]
  serialize :answers, Array

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :for_today, -> { where("created_at >= ?", Date.today.beginning_of_day) }

  def participant
    standup.standup_participants.find_by(slack_id: slack_id)
  end
end

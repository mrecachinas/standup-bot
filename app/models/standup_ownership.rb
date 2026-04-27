class StandupOwnership < ApplicationRecord
  ROLES = %w[manager owner].freeze

  belongs_to :standup
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :standup_id }
end

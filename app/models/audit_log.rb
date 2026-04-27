class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  attribute :metadata, :json, default: -> { {} }

  validates :action, presence: true
  validates :auditable_type, presence: true
  validates :auditable_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_auditable, ->(record) { where(auditable_type: record.class.name, auditable_id: record.id) }
end

class ReportGeneration < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :standup
  belongs_to :report_configuration, optional: true
  belongs_to :actor, class_name: "User", optional: true

  attribute :recipients, :json, default: -> { [] }
  attribute :metadata, :json, default: -> { {} }

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_channel, presence: true
  validates :report_format, inclusion: { in: ReportConfiguration::REPORT_FORMATS.keys }
  validates :detail_level, inclusion: { in: ReportConfiguration::DETAIL_LEVELS.keys }
  validates :standup_date, :requested_at, presence: true

  scope :recent, -> { order(requested_at: :desc, created_at: :desc) }

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def mark_running!
    update!(status: "running", started_at: Time.current)
  end

  def mark_succeeded!(metadata: {})
    update!(
      status: "succeeded",
      completed_at: Time.current,
      error_message: nil,
      metadata: merged_metadata(metadata)
    )
  end

  def mark_failed!(message, metadata: {})
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: message.to_s.truncate(2_000),
      metadata: merged_metadata(metadata)
    )
  end

  def delivery_targets
    [ delivery_channel, *Array(recipients) ].reject(&:blank?)
  end

  private

  def merged_metadata(new_metadata)
    metadata.to_h.merge(new_metadata.to_h.stringify_keys)
  end
end

class ReportConfiguration < ApplicationRecord
  REPORT_FORMATS = {
    "slack" => "Slack message",
    "plain_text" => "Plain text"
  }.freeze
  DETAIL_LEVELS = {
    "summary" => "Summary only",
    "detailed" => "Detailed Q&A"
  }.freeze

  belongs_to :standup
  has_many :report_generations, dependent: :nullify

  attribute :recipients, :json, default: -> { [] }

  before_validation :normalize_delivery_channel
  before_validation :normalize_recipients

  validates :delivery_channel, presence: true
  validate :delivery_channel_must_match_platform
  validates :report_format, inclusion: { in: REPORT_FORMATS.keys }
  validates :detail_level, inclusion: { in: DETAIL_LEVELS.keys }
  validate :recipients_are_valid

  def recipients_text
    Array(recipients).join("\n")
  end

  def recipients_text=(value)
    self.recipients = value.to_s.split(/[\n,]+/).map { |recipient| normalize_identifier(recipient) }.reject(&:blank?).uniq
  end

  private

  def normalize_delivery_channel
    self.delivery_channel = normalize_identifier(delivery_channel)
  end

  def normalize_recipients
    self.recipients = Array(recipients).map { |recipient| normalize_identifier(recipient) }.reject(&:blank?).uniq
  end

  def normalize_identifier(value)
    value.to_s.strip.sub(/\A#/, "")
  end

  def chat_platform
    ChatPlatform.for_standup(standup)
  end

  def delivery_channel_must_match_platform
    return if delivery_channel.blank? || chat_platform.valid_channel?(delivery_channel)

    errors.add(:delivery_channel, "must be #{chat_platform.channel_hint}")
  end

  def recipients_are_valid
    invalid_recipients = Array(recipients).reject do |recipient|
      chat_platform.valid_channel?(recipient) || chat_platform.valid_user_id?(recipient)
    end
    return if invalid_recipients.empty?

    errors.add(:recipients, "contain invalid #{chat_platform.label} channel or user IDs: #{invalid_recipients.join(', ')}")
  end
end

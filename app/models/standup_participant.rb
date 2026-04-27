class StandupParticipant < ApplicationRecord
  DEFAULT_TIMEZONE = "UTC"
  TIMEZONE_CACHE_TTL = 1.week

  belongs_to :standup

  validates :slack_id, presence: true
  validates :slack_id, uniqueness: { scope: :standup_id }
  validate :cached_timezone_must_be_valid

  scope :active, -> { where(active: true) }
  scope :available_on, ->(date) { active.where("vacation_until IS NULL OR vacation_until < ?", date) }

  # Fetch participant info from Slack as needed
  def fetch_info
    SlackClient.instance.get_user_info(slack_id)
  end

  def timezone
    return cached_timezone if cached_timezone_available?

    refresh_timezone || valid_cached_timezone || DEFAULT_TIMEZONE
  end

  def time_zone
    Standup.resolve_time_zone(timezone)
  end

  def refresh_timezone
    info = fetch_info
    resolved_timezone = normalize_timezone(info&.dig("tz"))

    cache_timezone(resolved_timezone)
    resolved_timezone
  rescue StandardError => error
    Rails.logger.warn "Unable to refresh timezone for participant #{id || slack_id}: #{error.class} - #{error.message}"
    nil
  end

  def timezone_stale?
    return true if cached_timezone.blank?
    return false unless has_attribute?(:cached_timezone_updated_at)

    cached_timezone_updated_at.blank? || cached_timezone_updated_at < TIMEZONE_CACHE_TTL.ago
  end

  def standup_time_zone
    if standup.respect_timezone
      time_zone
    else
      Standup.resolve_time_zone(DEFAULT_TIMEZONE)
    end
  end

  def standup_date_for(time = Time.current)
    time.in_time_zone(standup_time_zone).to_date
  end

  def available_on?(date)
    active? && (vacation_until.blank? || vacation_until < date)
  end

  def calculate_send_time
    standup.next_occurrence_in_timezone(standup_time_zone).in_time_zone(DEFAULT_TIMEZONE)
  end

  def self.valid_timezone?(timezone_name)
    return false if timezone_name.blank?

    Time.find_zone(timezone_name).present? || TZInfo::Timezone.get(timezone_name).present?
  rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
    false
  end

  private

  def cached_timezone_available?
    valid_cached_timezone.present? && !timezone_stale?
  end

  def valid_cached_timezone
    cached_timezone if self.class.valid_timezone?(cached_timezone)
  end

  def normalize_timezone(timezone_name)
    self.class.valid_timezone?(timezone_name) ? timezone_name : DEFAULT_TIMEZONE
  end

  def cache_timezone(timezone_name)
    return unless persisted?

    attributes = { cached_timezone: timezone_name }
    attributes[:cached_timezone_updated_at] = Time.current if has_attribute?(:cached_timezone_updated_at)

    update_columns(attributes)
  end

  def cached_timezone_must_be_valid
    return if cached_timezone.blank? || self.class.valid_timezone?(cached_timezone)

    errors.add(:cached_timezone, "is not a valid timezone")
  end
end

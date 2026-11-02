class StandupParticipant < ApplicationRecord
  DEFAULT_TIMEZONE = "UTC"
  TIMEZONE_CACHE_TTL = 1.week
  belongs_to :standup

  before_validation :normalize_fields
  before_save :touch_cached_timezone_updated_at, if: :should_touch_cached_timezone_updated_at?

  validates :platform_user_id, presence: true
  validate :platform_user_id_must_match_platform
  validates :display_name, presence: true
  validates :platform_user_id, uniqueness: { scope: :standup_id }
  validate :cached_timezone_must_be_valid

  scope :active, -> { where(active: true) }
  normalizes :avatar_url, with: ->(url) { AvatarUrl.sanitize(url) }

  scope :on_platform, ->(platform) { joins(:standup).where(standups: { platform: platform.to_s }) }
  # This person's rows in standups that are still running, whether or not they're away.
  scope :in_active_standups, ->(platform, platform_user_id) {
    on_platform(platform).merge(Standup.active).where(platform_user_id: platform_user_id)
  }
  scope :available_on, ->(date) { active.where("vacation_until IS NULL OR vacation_until < ?", date) }

  def fetch_profile
    ChatPlatform.for_standup(standup).user_profile(platform_user_id)
  end

  def timezone
    return cached_timezone if cached_timezone_available?

    refresh_timezone || valid_cached_timezone || DEFAULT_TIMEZONE
  end

  def time_zone
    Standup.resolve_time_zone(timezone)
  end

  def refresh_timezone
    profile = fetch_profile
    resolved_timezone = normalize_timezone(profile&.timezone)

    cache_timezone(resolved_timezone)
    cache_avatar_url(profile&.avatar_url)
    resolved_timezone
  rescue StandardError => error
    Rails.logger.warn "Unable to refresh timezone for participant #{id || platform_user_id}: #{error.class} - #{error.message}"
    nil
  end

  def timezone_stale?
    return true if cached_timezone.blank?
    return false unless has_attribute?(:cached_timezone_updated_at)

    cached_timezone_updated_at.blank? || cached_timezone_updated_at < TIMEZONE_CACHE_TTL.ago
  end

  def timezone_cache_status
    return "missing" if cached_timezone.blank?
    return "invalid" unless self.class.valid_timezone?(cached_timezone)

    timezone_stale? ? "stale" : "fresh"
  end

  def timezone_cache_status_description
    case timezone_cache_status
    when "fresh"
      "Synced #{cached_timezone_updated_at&.to_fs(:long) || 'recently'}"
    when "stale"
      "Needs sync"
    when "invalid"
      "Invalid timezone"
    else
      "Not cached"
    end
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

  def vacation_status_on(date = Date.current)
    if vacation_until.present? && vacation_until >= date
      "Away through #{vacation_until.iso8601}"
    elsif vacation_until.present?
      "Returned after #{vacation_until.iso8601}"
    else
      "No vacation recorded"
    end
  end

  def calculate_send_time
    next_standup_occurrence&.scheduled_at&.in_time_zone(DEFAULT_TIMEZONE)
  end

  def next_standup_occurrence
    standup.next_occurrence_detail_in_timezone(standup_time_zone)
  end

  def self.valid_timezone?(timezone_name)
    return false if timezone_name.blank?

    Time.find_zone(timezone_name).present? || TZInfo::Timezone.get(timezone_name).present?
  rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
    false
  end

  private

  def chat_platform
    ChatPlatform.for_standup(standup)
  end

  def platform_user_id_must_match_platform
    return if platform_user_id.blank? || chat_platform.valid_user_id?(platform_user_id)

    errors.add(:platform_user_id, "must be #{chat_platform.user_id_hint}")
  end

  def normalize_fields
    self.platform_user_id = chat_platform.normalize_user_id(platform_user_id) if platform_user_id.present?
    self.display_name = display_name.to_s.strip if display_name.present?
    self.cached_timezone = cached_timezone.strip if cached_timezone.present?
  end

  def should_touch_cached_timezone_updated_at?
    has_attribute?(:cached_timezone_updated_at) &&
      cached_timezone.present? &&
      will_save_change_to_cached_timezone? &&
      !will_save_change_to_cached_timezone_updated_at?
  end

  def touch_cached_timezone_updated_at
    self.cached_timezone_updated_at = Time.current
  end

  def cached_timezone_available?
    valid_cached_timezone.present? && !timezone_stale?
  end

  def valid_cached_timezone
    cached_timezone if self.class.valid_timezone?(cached_timezone)
  end

  def normalize_timezone(timezone_name)
    self.class.valid_timezone?(timezone_name) ? timezone_name : DEFAULT_TIMEZONE
  end

  def cache_avatar_url(url)
    return unless persisted? && AvatarUrl.safe?(url) && url != avatar_url

    update_columns(avatar_url: url)
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

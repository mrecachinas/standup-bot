# Picks a small profile photo URL out of a Slack profile, skipping any that
# AvatarUrl wouldn't accept.
module SlackAvatar
  SIZES = %w[image_72 image_48 image_192 image_32 image_24].freeze

  def self.url_from(profile)
    return if profile.blank?

    SIZES.each do |key|
      url = value(profile, key)
      return url if AvatarUrl.safe?(url)
    end
    nil
  end

  def self.value(profile, key)
    profile[key] || profile[key.to_sym]
  rescue StandardError
    nil
  end
end

# Picks a small profile photo URL out of a Slack profile. Only https URLs are
# kept so a stored value can't be used to inject a different kind of link.
module SlackAvatar
  SIZES = %w[image_72 image_48 image_192 image_32 image_24].freeze

  def self.url_from(profile)
    return if profile.blank?

    SIZES.each do |key|
      url = value(profile, key)
      return url if safe_url?(url)
    end
    nil
  end

  def self.safe_url?(url)
    url.is_a?(String) && url.start_with?("https://") && url.length <= 1024
  end

  def self.value(profile, key)
    profile[key] || profile[key.to_sym]
  rescue StandardError
    nil
  end
end

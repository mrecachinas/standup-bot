# UI wording that differs between chat platforms.
module ChatPlatformHelper
  PLATFORM_COPY = PlatformSerializer::COPY

  def platform_copy(platform, key)
    PLATFORM_COPY.fetch(platform.to_s.presence&.to_sym || ChatPlatform::DEFAULT).fetch(key)
  end

  def platform_label(platform)
    ChatPlatform.for(platform).label
  end

  def platform_icon(platform)
    platform_copy(platform, :icon)
  end

  # Signed-in member's platform, for copy in the member area.
  def member_platform_label
    current_member ? platform_label(current_member.platform) : "your chat app"
  end
end

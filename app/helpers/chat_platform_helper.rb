# UI wording that differs between chat platforms.
module ChatPlatformHelper
  PLATFORM_COPY = {
    slack: {
      icon: :hash,
      user_placeholder: "@jane, Jane Doe, or U123ABC",
      user_lookup_hint: "Use a Slack @username, display name, mention, or user ID. Name and timezone are looked up in Slack.",
      user_search_placeholder: "Search by name, @username, or ID",
      import_placeholder: "@alice\n<@U456|Bob>\nU789,Carol,Europe/London,true",
      import_hint: "Slack username, mention, or ID. Optional extra columns: name, timezone, active.",
      channel_id_placeholder: "Channel ID, like C0123",
      channel_search_placeholder: "Search channels by name or ID",
      recipients_placeholder: "One Slack user or channel ID per line",
      recipients_hint: "Optional. Slack user IDs get a DM; channel IDs get a post."
    },
    teams: {
      icon: :users,
      user_placeholder: "jane@contoso.com, Jane Doe, or an object ID",
      user_lookup_hint: "Use a Teams name, email, or Microsoft Entra object ID. Names and timezones are looked up in Microsoft 365.",
      user_search_placeholder: "Search by name or email",
      import_placeholder: "alice@contoso.com\nBob Smith\n00000000-0000-0000-0000-000000000000,Carol,Europe/London,true",
      import_hint: "Teams name, email, or object ID. Optional extra columns: name, timezone, active.",
      channel_id_placeholder: "TEAM_ID|19:…@thread.tacv2",
      channel_search_placeholder: "Search by team or channel name",
      recipients_placeholder: "One Entra object ID or TEAM_ID|CHANNEL_ID per line",
      recipients_hint: "Optional. People get a Teams chat; channels get a new post."
    }
  }.freeze

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

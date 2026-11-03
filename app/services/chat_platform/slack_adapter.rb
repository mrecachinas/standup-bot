module ChatPlatform
  # Slack implementation of the adapter contract. SlackClient stays the
  # low-level Web API wrapper; Block Kit and mrkdwn live here.
  class SlackAdapter < Adapter
    USER_ID_PATTERN = /\A[UW][A-Z0-9]{2,}\z/
    CHANNEL_PATTERN = /\A#?[A-Za-z0-9][A-Za-z0-9_-]*\z/

    def key
      :slack
    end

    def label
      "Slack"
    end

    def configured?
      SlackConfig.configured?
    end

    def formatter
      SlackFormatter
    end

    def send_direct_message(user_id, text)
      send_message(user_id, text)
    end

    def send_message(target, text)
      to_message_ref(client.send_message(target, text))
    end

    def post_standup_update(channel, display_name:, answers:)
      send_message(channel, standup_update_text(display_name, answers))
    end

    def update_standup_update(channel, message_id, display_name:, answers:)
      blocks = [ standup_update_heading(display_name), *answer_sections(answers) ].map do |text|
        { type: "section", text: { type: "mrkdwn", text: text } }
      end

      client.update_message(channel, message_id, standup_update_text(display_name, answers), blocks)
    end

    def post_report(channel, text, outro: nil)
      to_message_ref(client.send_standup_summary(channel, text, outro))
    end

    def send_selection(target, text, options, action_id:)
      to_message_ref(client.send_standup_selection(target, text, options, action_id: action_id))
    end

    def selection_blocks(text, options, action_id:)
      SlackClient.selection_blocks(text, options, action_id: action_id)
    end

    def user_profile(user_id)
      info = client.get_user_info(user_id)
      return if info.blank?

      profile = info["profile"] || {}
      UserProfile.new(
        id: user_id,
        name: info["name"],
        display_name: profile_value(profile, "display_name"),
        real_name: profile_value(profile, "real_name"),
        email: profile_value(profile, "email"),
        timezone: info["tz"],
        avatar_url: info["avatar_url"],
        deleted: info["deleted"] == true,
        bot: info["is_bot"] == true,
        guest: info["is_restricted"] == true || info["is_ultra_restricted"] == true
      )
    end

    def search_users(query: nil, limit: 100)
      client.list_users(query: query, limit: limit)
    end

    def list_channels(query: nil, limit: 100)
      client.list_channels(query: query, limit: limit)
    end

    def channel_member_ids(channel)
      client.channel_members(channel)
    end

    def channel_member_profiles(channel)
      client.channel_member_profiles(channel)
    end

    def connection_status
      client.auth_test
    end

    def valid_user_id?(value)
      USER_ID_PATTERN.match?(value.to_s)
    end

    def normalize_user_id(value)
      value.to_s.strip.upcase.presence
    end

    # Also accepts lowercase or partly typed IDs like "u123".
    def looks_like_user_id?(value)
      value = value.to_s.strip
      upcased = value.upcase
      (value == upcased && valid_user_id?(upcased)) || upcased.match?(/\A[UW][A-Z0-9]*\d[A-Z0-9]*\z/)
    end

    def user_id_hint
      "a Slack user ID like U123ABC"
    end

    def valid_channel?(value)
      CHANNEL_PATTERN.match?(value.to_s)
    end

    def normalize_channel(value)
      value.to_s.strip.delete_prefix("#").presence
    end

    def channel_hint
      "a Slack channel name or ID without spaces"
    end

    private

    # Looked up per call so test stubs of SlackClient.instance take effect.
    def client
      SlackClient.instance
    end

    def to_message_ref(response)
      MessageRef.from_hash(response, id_key: "ts")
    end

    def profile_value(profile, key)
      profile[key] || profile[key.to_sym] if profile.respond_to?(:[])
    end
  end
end

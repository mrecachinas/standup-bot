module ChatPlatform
  # Slack implementation of the adapter contract. SlackClient stays the
  # low-level Web API wrapper; Block Kit and mrkdwn live here.
  class SlackAdapter < Adapter
    USER_ID_PATTERN = /\A[UW][A-Z0-9]{2,}\z/
    SLACKBOT_ID = "USLACKBOT".freeze
    CHANNEL_PATTERN = /\A#?[A-Za-z0-9][A-Za-z0-9_-]*\z/
    # Left-bar colors for the answers in a channel update, in question order.
    ANSWER_COLORS = %w[#4FB3A9 #7A8FD6 #E07B85 #E5A84B #9C7DD1].freeze
    # Slack's limit for a section block's text.
    SECTION_TEXT_LIMIT = 3000

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

    # The visible heading is a block; the top-level text keeps the whole update,
    # because notifications and screen readers read that rather than the blocks.
    def post_standup_update(channel, display_name:, standup_name:, answers:, edited: false)
      to_message_ref(
        client.send_message(
          channel,
          standup_update_text(display_name, standup_name, answers, edited: edited),
          section_blocks(standup_update_heading(display_name, standup_name, answers, edited: edited)),
          attachments: answer_attachments(answers)
        )
      )
    end

    def update_standup_update(channel, message_id, display_name:, standup_name:, answers:, edited: false)
      client.update_message(
        channel,
        message_id,
        standup_update_text(display_name, standup_name, answers, edited: edited),
        section_blocks(standup_update_heading(display_name, standup_name, answers, edited: edited)),
        attachments: answer_attachments(answers)
      )
    end

    def send_standup_kickoff(user_id, standup_name:, channel:, intro:, question:, question_count:, channel_name: nil, wrapped_up_previous: false, menu: nil)
      parts = standup_kickoff_parts(
        user_id,
        standup_name: standup_name, channel: channel, channel_name: channel_name, intro: intro,
        question: question, question_count: question_count, wrapped_up_previous: wrapped_up_previous
      )
      greeting_blocks = section_blocks(parts[:greeting])
      greeting_blocks[0] = greeting_blocks[0].merge(accessory: menu_select(menu)) if menu
      blocks = [
        *(section_blocks(parts[:wrapped_up]) if parts[:wrapped_up]),
        { type: "context", elements: [ { type: "mrkdwn", text: parts[:context] } ] },
        { type: "divider" },
        *greeting_blocks,
        *section_blocks(parts[:question])
      ]
      # Screen readers and notifications use this text, so it carries everything,
      # including the question count and how to skip.
      fallback = parts.values_at(:wrapped_up, :context, :greeting, :question).compact.join("\n\n")

      to_message_ref(client.send_message(user_id, fallback, blocks))
    end

    # Links to the channel when it's stored as an ID, so Slack shows its current name.
    def channel_mention(channel, name: nil)
      return "<##{channel}>" if channel.to_s.match?(SlackClient::CHANNEL_ID_PATTERN)

      super
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

    def send_action(target, text, button:, action_id:)
      to_message_ref(client.send_message(target, text, action_blocks(text, button: button, action_id: action_id)))
    end

    def action_blocks(text, button:, action_id:)
      [
        section_block(text).merge(
          accessory: {
            type: "button",
            text: { type: "plain_text", text: button[:text].to_s },
            action_id: action_id,
            value: button[:value].to_s
          }
        )
      ]
    end

    # Block Kit for a command reply, or nil when plain text will do.
    def reply_blocks(reply)
      if reply.selection?
        selection_blocks(reply.text, reply.options, action_id: reply.action_id)
      elsif reply.action?
        action_blocks(reply.text, button: reply.button, action_id: reply.action_id)
      end
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

    def list_channels(query: nil, limit: 100, include_private: true)
      client.list_channels(query: query, limit: limit, include_private: include_private)
    end

    def channel_member_ids(channel)
      client.channel_members(channel)
    end

    # Skips bots (including this app), Slackbot, and deactivated accounts, the
    # same people user search leaves out. Guests are kept, as they are there.
    def channel_member_profiles(channel)
      channel_member_ids(channel).filter_map do |user_id|
        next if user_id == SLACKBOT_ID

        profile = user_profile(user_id)
        next if profile.nil? || profile.bot? || profile.deleted?

        {
          "platform_user_id" => user_id,
          "display_name" => profile.preferred_name || user_id,
          "cached_timezone" => profile.timezone.presence,
          "avatar_url" => profile.avatar_url
        }.compact
      end
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

    def section_block(text)
      { type: "section", text: { type: "mrkdwn", text: text } }
    end

    # Section blocks for text of any length, split under Slack's limit.
    def section_blocks(text)
      split_mrkdwn(text).map { |chunk| section_block(chunk) }
    end

    # Splits mrkdwn into chunks under the section limit, preferring line breaks,
    # then spaces, and never cutting through <...> links, mentions, or channels,
    # which would stop rendering if split across two sections.
    def split_mrkdwn(text, limit = SECTION_TEXT_LIMIT)
      chunks = []
      rest = text.to_s

      while rest.length > limit
        cut = mrkdwn_cut_point(rest, limit)
        chunks << rest[0...cut]
        rest = rest[cut..].sub(/\A[ \n]+/, "")
      end

      chunks << rest
    end

    def mrkdwn_cut_point(text, limit)
      depth = 0
      last_newline = last_space = last_safe = nil

      text[0...limit].each_char.with_index do |char, index|
        depth += 1 if char == "<"
        depth -= 1 if char == ">" && depth.positive?
        next unless depth.zero?

        last_safe = index + 1
        # A break near the start would leave a tiny section, so only use breaks in the second half.
        next if index < limit / 2

        last_newline = index + 1 if char == "\n"
        last_space = index + 1 if char == " "
      end

      last_newline || last_space || last_safe || limit
    end

    # One colored bar per answer, with the question in bold above it.
    def answer_attachments(answers)
      answers.each_with_index.map do |answer, index|
        text = "#{formatter.bold(answer[:question])}\n#{answer[:answer]}"
        {
          color: ANSWER_COLORS[index % ANSWER_COLORS.size],
          fallback: "#{answer[:question]}: #{answer[:answer]}",
          blocks: section_blocks(text)
        }
      end
    end

    # A dropdown shown beside a section, like the kickoff's "Not today?" menu.
    def menu_select(menu)
      {
        type: "static_select",
        action_id: menu[:action_id],
        placeholder: { type: "plain_text", text: menu[:placeholder].to_s },
        options: menu[:options].map do |option|
          { text: { type: "plain_text", text: option[:text].to_s }, value: option[:value].to_s }
        end
      }
    end


    def to_message_ref(response)
      MessageRef.from_hash(response, id_key: "ts")
    end

    def profile_value(profile, key)
      profile[key] || profile[key.to_sym] if profile.respond_to?(:[])
    end
  end
end

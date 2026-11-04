class SlackClient
  MAX_RATE_LIMIT_RETRIES = 3
  CHANNEL_ID_PATTERN = /\A[CGD][A-Z0-9]+\z/
  CHANNEL_TYPES = "public_channel,private_channel".freeze
  PUBLIC_CHANNEL_TYPES = "public_channel".freeze
  PRIVATE_CHANNEL_SCOPE = "groups:read".freeze
  PRIVATE_CHANNELS_HIDDEN_NOTICE = "Private channels aren't listed because the Slack app doesn't have the " \
    "#{PRIVATE_CHANNEL_SCOPE} scope. Add it under OAuth & Permissions and reinstall the app to include them.".freeze
  PAGE_SIZE = 200

  def initialize
    @client = Slack::Web::Client.new(token: slack_bot_token, default_max_retries: MAX_RATE_LIMIT_RETRIES)
  end

  class << self
    def instance
      @instance ||= new
    end

    def reset!
      @instance = nil
    end

    def selection_blocks(text, options, action_id:)
      [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: text
          }
        },
        {
          type: "actions",
          elements: [
            {
              type: "static_select",
              placeholder: {
                type: "plain_text",
                text: "Select a standup"
              },
              action_id: action_id,
              options: options.map do |option|
                {
                  text: {
                    type: "plain_text",
                    text: option[:text]
                  },
                  value: option[:value].to_s
                }
              end
            }
          ]
        }
      ]
    end
  end

  def send_message(channel, text, blocks = nil, attachments: nil)
    message = { channel: channel, text: text, as_user: true }
    message[:blocks] = blocks if blocks
    message[:attachments] = attachments if attachments

    response = with_rate_limit_handling("send_message") do
      @client.chat_postMessage(**message)
    end

    StandupMetrics.track("slack.message_sent", channel: channel, blocks: blocks.present?)
    normalize_message_response(response)
  rescue => e
    Rails.logger.error "Error sending Slack message: #{e.class} - #{e.message}"
    StandupMetrics.track("slack.message_failed", channel: channel, error_class: e.class.name)
    raise
  end

  def get_user_info(slack_id)
    response = with_rate_limit_handling("get_user_info") do
      @client.users_info(user: slack_id)
    end
    user = response.user

    {
      "name" => user.name,
      "tz" => user.tz,
      "tz_offset" => user.tz_offset,
      "profile" => user.profile,
      "avatar_url" => SlackAvatar.url_from(user.profile),
      "deleted" => user.deleted,
      "is_bot" => user.is_bot,
      "is_restricted" => user.is_restricted,
      "is_ultra_restricted" => user.is_ultra_restricted
    }
  rescue Slack::Web::Api::Errors::UserNotFound
    Rails.logger.error "User not found in Slack: #{slack_id}"
    nil
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Faraday::Error => e
    Rails.logger.error "Error fetching user info: #{e.class} - #{e.message}"
    nil
  end

  def auth_test
    response = with_rate_limit_handling("auth_test") do
      @client.auth_test
    end

    normalize_hash_response(response, %w[ok team team_id user user_id bot_id url])
  end

  # Private channels need the groups:read scope. Installs from older
  # manifests don't have it, so fall back to public channels and say so.
  def list_channels(query: nil, limit: 100, include_private: true)
    response, private_listed = with_private_channel_fallback(include_private) do |types|
      with_rate_limit_handling("list_channels") do
        @client.conversations_list(exclude_archived: true, limit: limit, types: types)
      end
    end

    channels = Array(response["channels"]).filter_map { |channel| normalize_channel(channel) }
    notice = PRIVATE_CHANNELS_HIDDEN_NOTICE if include_private && !private_listed
    ChatPlatform::ChannelList.new(filter_records(channels, query, "id", "name", "label"), notice: notice)
  end

  def list_users(query: nil, limit: 100)
    response = with_rate_limit_handling("list_users") do
      @client.users_list(limit: limit)
    end

    users = Array(response["members"]).filter_map { |user| normalize_user(user) }
    filter_records(users, query, "id", "name", "display_name", "real_name", "label")
  end

  # Raises ChatPlatform::ChannelAccessError rather than returning an empty
  # list, so callers can tell people what went wrong.
  def channel_members(channel)
    channel_id = resolve_channel_id(channel)
    members = []
    @client.conversations_members(channel: channel_id, limit: PAGE_SIZE) do |page|
      members.concat(page.members)
    end
    members
  rescue Slack::Web::Api::Errors::ChannelNotFound
    Rails.logger.warn "Slack channel not found: #{channel}"
    raise ChatPlatform::ChannelAccessError, channel_not_found_message(channel)
  rescue Slack::Web::Api::Errors::MissingScope
    raise ChatPlatform::ChannelAccessError,
      "The Slack app can't read that channel's members. Add the #{PRIVATE_CHANNEL_SCOPE} scope for private channels, then try again."
  end

  def send_standup_selection(channel, text, options, action_id: "standup_selection")
    blocks = self.class.selection_blocks(text, options, action_id: action_id)

    with_rate_limit_handling("send_standup_selection") do
      @client.chat_postMessage(channel: channel, blocks: blocks, text: text, as_user: true)
    end
  end

  def send_standup_summary(channel, summary_text, outro = nil)
    blocks = [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "Daily Standup Summary"
        }
      },
      { type: "divider" },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: summary_text
        }
      }
    ]

    if outro.present?
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: outro
        }
      }
    end

    with_rate_limit_handling("send_standup_summary") do
      @client.chat_postMessage(channel: channel, blocks: blocks, text: "Daily Standup Summary", as_user: true)
    end
  end

  def update_message(channel, message_ts, text, blocks = nil, attachments: nil)
    message = { channel: channel, ts: message_ts, text: text, as_user: true }
    message[:blocks] = blocks if blocks
    message[:attachments] = attachments if attachments

    with_rate_limit_handling("update_message") do
      @client.chat_update(**message)
    end
  end

  private

  def normalize_hash_response(response, keys)
    keys.each_with_object({}) do |key, payload|
      value = response[key]
      payload[key] = value if value.present? || value == false
    end
  end

  def normalize_channel(channel)
    id = channel["id"]
    name = channel["name"] || channel["name_normalized"]
    return if id.blank? || name.blank?

    {
      "id" => id,
      "name" => name,
      "label" => "##{name}",
      "is_private" => channel["is_private"] == true,
      "is_member" => channel["is_member"] == true,
      "num_members" => channel["num_members"]
    }.compact
  end

  def normalize_user(user)
    id = user["id"]
    return if id.blank? || id == "USLACKBOT"
    return if user["deleted"] == true || user["is_bot"] == true

    profile = user["profile"] || {}
    display_name = profile["display_name"]
    real_name = user["real_name"] || profile["real_name"]
    username = user["name"]

    {
      "id" => id,
      "name" => username,
      "display_name" => display_name,
      "real_name" => real_name,
      "label" => display_name.presence || real_name.presence || username.presence || id,
      "tz" => user["tz"],
      "avatar_url" => SlackAvatar.url_from(profile)
    }.compact
  end

  def normalize_message_response(response)
    return response if response.blank?

    { "ok" => response["ok"], "channel" => response["channel"], "ts" => response["ts"] }.compact
  end

  def filter_records(records, query, *keys)
    return records if query.blank?

    normalized_query = query.to_s.downcase
    records.select do |record|
      keys.any? { |key| record[key].to_s.downcase.include?(normalized_query) }
    end
  end

  def slack_bot_token
    slack_config = Rails.application.config.slack || {}
    token = slack_config[:bot_token] || slack_config["bot_token"]
    Rails.logger.warn "Slack bot token is not configured" if token.blank?
    token
  end

  def resolve_channel_id(channel)
    name = channel.to_s.strip.delete_prefix("#")
    return name if name.match?(CHANNEL_ID_PATTERN)

    response, private_listed = with_private_channel_fallback do |types|
      @client.conversations_id(
        channel: "##{name}",
        id_types: types,
        id_exclude_archived: true,
        id_limit: PAGE_SIZE
      )
    rescue Slack::Web::Api::Errors::ChannelNotFound
      nil
    end

    channel_id = response&.dig("channel", "id")
    return channel_id if channel_id.present?

    message = channel_not_found_message(name)
    message += " Private channels can't be found until the Slack app has the #{PRIVATE_CHANNEL_SCOPE} scope." unless private_listed
    raise ChatPlatform::ChannelAccessError, message
  end

  def channel_not_found_message(channel)
    channel = channel.to_s.strip.delete_prefix("#")
    label = channel.match?(CHANNEL_ID_PATTERN) ? channel : "##{channel}"
    "Slack couldn't find #{label}. Check the channel, and invite the bot if it's private."
  end

  # Yields the conversation types to request, falling back to public channels
  # when the token lacks the private-channel scope. Returns the block's result
  # and whether private channels were included.
  def with_private_channel_fallback(include_private = true)
    return [ yield(PUBLIC_CHANNEL_TYPES), false ] unless include_private

    begin
      [ yield(CHANNEL_TYPES), true ]
    rescue Slack::Web::Api::Errors::MissingScope
      Rails.logger.warn "Slack app is missing the #{PRIVATE_CHANNEL_SCOPE} scope; listing public channels only"
      [ yield(PUBLIC_CHANNEL_TYPES), false ]
    end
  end

  def with_rate_limit_handling(operation)
    retries = 0

    begin
      yield
    rescue Slack::Web::Api::Errors::TooManyRequestsError => e
      StandupMetrics.track("slack.rate_limited", operation: operation)

      if retries < MAX_RATE_LIMIT_RETRIES
        retry_after = e.retry_after.positive? ? e.retry_after : 2**retries
        retries += 1
        Rails.logger.warn "Slack API rate limited during #{operation}; retrying #{retries}/#{MAX_RATE_LIMIT_RETRIES} after #{retry_after}s"
        sleep retry_after
        retry
      end

      Rails.logger.error "Slack API rate limit retries exhausted during #{operation}"
      raise
    end
  end
end

module ChatPlatform
  # Microsoft Teams implementation of the adapter contract.
  #
  # People are identified by their Entra object ID (a GUID). Standup channels
  # are "TEAM_ID|CHANNEL_ID", since Graph needs the team to list members and
  # the Bot Connector needs the channel to post. The bot sends DMs through a
  # 1:1 conversation it opens (or learns about from incoming activities) and
  # caches in ChatConversation.
  class TeamsAdapter < Adapter
    GUID_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    CHANNEL_PATTERN = /\A(?<team>\h{8}-\h{4}-\h{4}-\h{4}-\h{12})\|(?<channel>19:[^\s|]+)\z/i
    CARD_CONTENT_TYPE = "application/vnd.microsoft.card.adaptive".freeze
    # Listing channels takes a Graph call per team, so share the result briefly.
    CHANNEL_CACHE_TTL = 5.minutes
    MAX_TEAMS = 200

    NotInstalled = Class.new(Microsoft::ApiError)

    def initialize(connector: nil, graph: nil)
      @connector = connector
      @graph = graph
    end

    def key
      :teams
    end

    def label
      "Microsoft Teams"
    end

    def configured?
      Microsoft::Config.bot_configured?
    end

    def formatter
      TeamsFormatter
    end

    # Messaging

    def send_direct_message(user_id, text)
      deliver_direct(normalize_user_id(user_id), message_activity(text))
    end

    def send_message(target, text)
      deliver(target, message_activity(text))
    end

    def post_standup_update(channel, display_name:, standup_name:, answers:, edited: false)
      send_message(channel, standup_update_text(display_name, standup_name, answers, edited: edited))
    end

    def update_standup_update(channel, message_id, display_name:, standup_name:, answers:, edited: false)
      channel_id = parse_channel!(channel)[:channel]
      connector.update_activity(
        service_url: Microsoft::Config.service_url,
        conversation_id: "#{channel_id};messageid=#{message_id}",
        activity_id: message_id,
        activity: message_activity(standup_update_text(display_name, standup_name, answers, edited: edited))
      )
    end

    def post_report(channel, text, outro: nil)
      send_message(channel, [ formatter.bold("Daily Standup Summary"), text, outro.presence ].compact.join("\n\n"))
    end

    def send_selection(target, text, options, action_id:)
      deliver(target, selection_activity(text, options, action_id: action_id))
    end

    def send_action(target, text, button:, action_id:)
      deliver(target, action_activity(text, button: button, action_id: action_id))
    end

    def action_activity(text, button:, action_id:)
      {
        type: "message",
        text: text,
        attachments: [
          {
            contentType: CARD_CONTENT_TYPE,
            content: {
              type: "AdaptiveCard",
              "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
              version: "1.4",
              body: [ { type: "TextBlock", text: text, wrap: true } ],
              actions: [
                { type: "Action.Submit", title: button[:text].to_s, data: { action_id: action_id, standup_id: button[:value].to_s } }
              ]
            }
          }
        ]
      }
    end

    def selection_activity(text, options, action_id:)
      {
        type: "message",
        text: text,
        attachments: [
          {
            contentType: CARD_CONTENT_TYPE,
            content: {
              type: "AdaptiveCard",
              "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
              version: "1.4",
              body: [
                { type: "TextBlock", text: text, wrap: true },
                {
                  type: "Input.ChoiceSet",
                  id: "standup_id",
                  style: "compact",
                  placeholder: "Select a standup",
                  choices: options.map { |option| { title: option[:text].to_s, value: option[:value].to_s } }
                }
              ],
              actions: [ { type: "Action.Submit", title: "Choose", data: { action_id: action_id } } ]
            }
          }
        ]
      }
    end

    # People and channels

    def user_profile(user_id)
      user = graph.user(user_id)
      UserProfile.new(
        id: user["id"],
        name: user["userPrincipalName"],
        display_name: user["displayName"],
        email: user["mail"].presence || user["userPrincipalName"],
        timezone: Microsoft::WindowsTimeZones.to_iana(graph.user_time_zone(user_id)),
        avatar_url: nil,
        deleted: user["accountEnabled"] == false,
        bot: false,
        guest: user["userType"].to_s.casecmp?("Guest")
      )
    rescue Microsoft::ApiError => error
      raise unless error.not_found?

      nil
    end

    def search_users(query: nil, limit: 100)
      graph.search_users(query, limit: limit).filter_map do |user|
        next if user["id"].blank? || user["accountEnabled"] == false || user["userType"].to_s.casecmp?("Guest")

        {
          "id" => user["id"],
          "name" => user["userPrincipalName"],
          "display_name" => user["displayName"],
          "real_name" => user["displayName"],
          "email" => user["mail"],
          "label" => user["displayName"].presence || user["userPrincipalName"].presence || user["id"]
        }.compact
      end
    end

    def list_channels(query: nil, limit: 100, include_private: true)
      records = all_channels
      records = records.reject { |record| record["is_private"] } unless include_private
      records = records.select { |record| record["label"].downcase.include?(query.to_s.downcase) } if query.present?
      records.first(limit)
    end

    def channel_member_ids(channel)
      channel_members(channel).filter_map { |member| member["userId"].presence&.downcase }
    end

    def channel_member_profiles(channel)
      channel_members(channel).filter_map do |member|
        user_id = member["userId"].presence&.downcase
        next unless user_id

        {
          "platform_user_id" => user_id,
          "display_name" => member["displayName"].presence || member["email"].presence || user_id,
          "cached_timezone" => Microsoft::WindowsTimeZones.to_iana(graph.user_time_zone(user_id))
        }.compact
      end
    end

    def connection_status
      Microsoft::TokenProvider.instance.token(Microsoft::TokenProvider::BOT_CONNECTOR_SCOPE)
      Microsoft::TokenProvider.instance.token(Microsoft::TokenProvider::GRAPH_SCOPE)
      { "ok" => true, "team_id" => Microsoft::Config.tenant_id, "app_id" => Microsoft::Config.app_id }
    end

    # Validation

    def valid_user_id?(value)
      GUID_PATTERN.match?(value.to_s.strip)
    end

    def normalize_user_id(value)
      value.to_s.strip.downcase.presence
    end

    def user_id_hint
      "a Microsoft Entra user object ID (a GUID)"
    end

    def valid_channel?(value)
      CHANNEL_PATTERN.match?(value.to_s.strip)
    end

    def normalize_channel(value)
      value.to_s.strip.presence
    end

    def channel_hint
      "a Teams channel picked from channel discovery"
    end

    # Inbound text can carry @mentions and HTML formatting.
    def plain_text(text)
      without_mentions = text.to_s.gsub(%r{<at>.*?</at>}im, " ")
      text = CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(without_mentions.gsub(%r{<br\s*/?>}i, "\n")))
      text.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").strip
    end

    # Keeps a 1:1 chat someone opened with the bot on file, so DMs to them
    # don't need to create one. Ignores service URLs we wouldn't call back.
    def remember_conversation(user_id:, conversation_id:, service_url:, tenant_id:)
      return unless Microsoft::BotConnectorClient.trusted_service_url?(service_url)

      ChatConversation.remember!(platform: key, platform_user_id: user_id, conversation_id: conversation_id, service_url: service_url, tenant_id: tenant_id)
    end

    private

    def connector
      @connector ||= Microsoft::BotConnectorClient.new
    end

    def graph
      @graph ||= Microsoft::GraphClient.new
    end

    def message_activity(text)
      { type: "message", textFormat: "markdown", text: text }
    end

    def parse_channel(value)
      CHANNEL_PATTERN.match(value.to_s.strip)
    end

    def parse_channel!(value)
      parse_channel(value) || raise(Microsoft::ApiError.new("#{value.inspect} isn't a Teams channel (expected TEAM_ID|CHANNEL_ID).", status: 400))
    end

    # A channel gets a new thread; a person gets a DM; anything else is an
    # existing conversation ID (for example, replying in the chat a message came from).
    def deliver(target, activity)
      if (channel = parse_channel(target))
        thread = connector.create_channel_thread(
          service_url: Microsoft::Config.service_url,
          channel_id: channel[:channel],
          tenant_id: Microsoft::Config.tenant_id,
          activity: activity
        )
        StandupMetrics.track("teams.message_sent", channel: target)
        MessageRef.new(channel: thread[:conversation_id], id: thread[:activity_id])
      elsif valid_user_id?(target)
        deliver_direct(normalize_user_id(target), activity)
      else
        conversation = ChatConversation.on_platform(key).find_by(conversation_id: target)
        id = connector.send_activity(
          service_url: conversation&.service_url.presence || Microsoft::Config.service_url,
          conversation_id: target,
          activity: activity
        )
        MessageRef.new(channel: target, id: id)
      end
    end

    def deliver_direct(user_id, activity)
      conversation = direct_conversation(user_id)
      id = connector.send_activity(
        service_url: conversation.service_url.presence || Microsoft::Config.service_url,
        conversation_id: conversation.conversation_id,
        activity: activity
      )
      StandupMetrics.track("teams.message_sent", channel: "direct")
      MessageRef.new(channel: conversation.conversation_id, id: id)
    end

    def direct_conversation(user_id)
      ChatConversation.on_platform(key).find_by(platform_user_id: user_id) || open_direct_conversation(user_id)
    end

    def open_direct_conversation(user_id, install: true)
      conversation_id = connector.create_personal_conversation(
        service_url: Microsoft::Config.service_url,
        user_id: user_id,
        tenant_id: Microsoft::Config.tenant_id
      )
      ChatConversation.remember!(platform: key, platform_user_id: user_id, conversation_id: conversation_id, service_url: Microsoft::Config.service_url, tenant_id: Microsoft::Config.tenant_id)
    rescue Microsoft::ApiError => error
      raise unless error.forbidden?

      if install && Microsoft::Config.app_catalog_id.present?
        graph.install_app_for_user(user_id, Microsoft::Config.app_catalog_id)
        return open_direct_conversation(user_id, install: false)
      end

      raise NotInstalled.new(
        "Couldn't open a Teams chat with #{user_id}: the Standup Bot app isn't installed for them. " \
          "Install it for them, or set TEAMS_APP_CATALOG_ID so the bot can install itself.",
        status: 403
      )
    end

    def all_channels
      Rails.cache.fetch("teams/channels/#{Microsoft::Config.tenant_id}", expires_in: CHANNEL_CACHE_TTL) do
        graph.teams(limit: MAX_TEAMS).flat_map do |team|
          graph.channels(team["id"]).map do |channel|
            label = "#{team['displayName']} › #{channel['displayName']}"
            {
              "id" => "#{team['id']}|#{channel['id']}",
              "name" => label,
              "label" => label,
              "team_id" => team["id"],
              "is_private" => channel["membershipType"].present? && channel["membershipType"] != "standard"
            }
          end
        end
      end
    end

    def channel_members(channel)
      parsed = parse_channel!(channel)
      graph.channel_members(parsed[:team], parsed[:channel])
    end
  end
end

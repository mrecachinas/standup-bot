module Api
  # Connection health and channel/people lookup for each chat platform. Like
  # the console page it replaces, any manager may open it; only admins see
  # private channels.
  class ChatIntegrationsController < BaseController
    before_action :require_manager!
    before_action :skip_authorization

    def show
      platform = params[:platform].presence_in(ChatPlatform.keys.map(&:to_s)) || default_platform
      statuses = ChatPlatform.keys.to_h { |key| [ key.to_s, ChatIntegrationService.for(key).configuration_status ] }
      integration_service = ChatIntegrationService.for(platform)
      channel_query = params[:channel_query].presence
      user_query = params[:user_query].presence
      channel_result = integration_service.discover_channels(query: channel_query, include_private: principal.admin?) if discovery_requested?("channels", channel_query)
      user_result = integration_service.discover_users(query: user_query) if discovery_requested?("users", user_query)

      render json: {
        platform: platform,
        platforms: statuses.map { |key, status| platform_tab(key, status) },
        integration_status: ChatStatusSerializer.new(statuses.fetch(platform), connection_result: integration_service.connection_status, platform: platform).as_json,
        copy: {
          channel_search_placeholder: PlatformSerializer.copy_for(platform, :channel_search_placeholder),
          user_search_placeholder: PlatformSerializer.copy_for(platform, :user_search_placeholder)
        },
        standups: manageable_standups.order(:name).map { |standup| standup_json(standup) },
        channel_query: channel_query,
        user_query: user_query,
        channel_result: ChatResultSerializer.new(channel_result, kind: :channels).as_json,
        user_result: ChatResultSerializer.new(user_result, kind: :users).as_json
      }
    end

    private

    def default_platform
      (ChatPlatform.enabled.first&.key || ChatPlatform::DEFAULT).to_s
    end

    def platform_tab(key, status)
      configured = status[:configured] || false
      {
        key: key,
        label: ChatPlatform.for(key).label,
        icon: PlatformSerializer::ICONS.fetch(key.to_sym),
        configured: configured,
        status_label: configured ? "Connected" : "Not set up",
        status_tone: configured ? "success" : "warning"
      }
    end

    def standup_json(standup)
      {
        id: standup.id,
        name: standup.name,
        active: standup.active,
        platform: standup.platform,
        platform_label: standup.chat_platform.label,
        platform_channel: standup.platform_channel,
        channel_reference: standup.channel_reference
      }
    end

    def discovery_requested?(type, query)
      query.present? || params[:discover] == type
    end
  end
end

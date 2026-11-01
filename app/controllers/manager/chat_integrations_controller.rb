module Manager
  # Connection health and channel/people lookup for each chat platform.
  class ChatIntegrationsController < ApplicationController
    before_action :skip_authorization

    def show
      @platform = params[:platform].presence_in(ChatPlatform.keys.map(&:to_s)) || default_platform
      @statuses = ChatPlatform.keys.to_h { |key| [ key.to_s, ChatIntegrationService.for(key).configuration_status ] }
      @integration_status = @statuses.fetch(@platform)
      @connection_result = integration_service.connection_status
      @standups = manageable_standups.order(:name)

      @channel_query = params[:channel_query]
      @user_query = params[:user_query]
      @channel_result = integration_service.discover_channels(query: @channel_query, include_private: current_user.admin?) if discovery_requested?("channels", @channel_query)
      @user_result = integration_service.discover_users(query: @user_query) if discovery_requested?("users", @user_query)
    end

    private

    def default_platform
      (ChatPlatform.enabled.first&.key || ChatPlatform::DEFAULT).to_s
    end

    def integration_service
      @integration_service ||= ChatIntegrationService.for(@platform)
    end

    def discovery_requested?(type, query)
      query.present? || params[:discover] == type
    end
  end
end

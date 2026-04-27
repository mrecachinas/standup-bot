module Manager
  class SlackIntegrationsController < ApplicationController
    def show
      @slack_integration_status = slack_integration_service.configuration_status
      @connection_result = slack_integration_service.connection_status
      @standups = manageable_standups.order(:name)

      @channel_query = params[:channel_query]
      @user_query = params[:user_query]
      @channel_result = slack_integration_service.discover_channels(query: @channel_query) if discovery_requested?("channels", @channel_query)
      @user_result = slack_integration_service.discover_users(query: @user_query) if discovery_requested?("users", @user_query)
    end

    private

    def slack_integration_service
      @slack_integration_service ||= SlackIntegrationService.new
    end

    def discovery_requested?(type, query)
      query.present? || params[:discover] == type
    end
  end
end

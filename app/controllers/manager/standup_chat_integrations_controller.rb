module Manager
  # The per-standup "Slack" / "Microsoft Teams" tab: pick the summary channel,
  # find and add people, and send a test message.
  class StandupChatIntegrationsController < ApplicationController
    before_action :set_standup

    def show
      load_chat_setup
    end

    def update_channel
      channel_id = params[:channel_id].to_s.strip
      channel_name = params[:channel_name].to_s.strip.presence

      if channel_id.blank?
        @channel_update_error = "Select a #{chat_platform.label} channel or enter a channel ID."
        load_chat_setup
        render :show, status: :unprocessable_entity
        return
      end

      previous_channel = @standup.platform_channel
      unless @standup.update(platform_channel: channel_id, platform_channel_name: channel_name)
        @channel_update_error = @standup.errors.full_messages.to_sentence
        load_chat_setup
        render :show, status: :unprocessable_entity
        return
      end

      audit_manager_change!(
        "#{@standup.platform}.channel.update",
        auditable: @standup,
        metadata: { previous_channel: previous_channel, platform_channel: channel_id, channel_name: channel_name }.compact
      )

      redirect_to manager_standup_chat_setup_path(@standup, channel_updated: "1"), status: :see_other
    end

    def add_participant
      identifier = params[:user].presence || params[:slack_user].presence || params[:platform_user_id]
      resolved_user = user_resolver.resolve(identifier, fallback_name: params[:display_name].to_s.strip.presence)
      platform_user_id = resolved_user.platform_user_id
      display_name = resolved_user.display_name

      if platform_user_id.blank?
        @participant_error = "Select a #{chat_platform.label} user before adding a participant."
        load_chat_setup
        render :show, status: :unprocessable_entity
        return
      end

      participant = @standup.standup_participants.find_or_initialize_by(platform_user_id: platform_user_id)
      participant.assign_attributes(display_name: display_name, active: true)
      participant.cached_timezone ||= resolved_user.cached_timezone
      participant.avatar_url = resolved_user.avatar_url if SlackAvatar.safe_url?(resolved_user.avatar_url)

      if participant.save
        audit_manager_change!(
          "#{@standup.platform}.participant.add",
          auditable: participant,
          metadata: { standup_id: @standup.id, platform_user_id: participant.platform_user_id, display_name: display_name }
        )
        redirect_to manager_standup_chat_setup_path(@standup, participant_added: "1"), status: :see_other
      else
        @participant_error = participant.errors.full_messages.to_sentence
        load_chat_setup
        render :show, status: :unprocessable_entity
      end
    rescue ChatUserResolver::ResolutionError => error
      @participant_error = error.message
      load_chat_setup
      render :show, status: :unprocessable_entity
    end

    def remove_participant
      participant = @standup.standup_participants.find(params[:participant_id])
      metadata = { standup_id: @standup.id, platform_user_id: participant.platform_user_id, display_name: participant.display_name }
      participant.destroy!
      audit_manager_change!("#{@standup.platform}.participant.remove", auditable: participant, metadata: metadata)

      redirect_to manager_standup_chat_setup_path(@standup, participant_removed: "1"), status: :see_other
    end

    def test_message
      @test_message_result = integration_service.test_message(@standup)
      audit_test_message!(@test_message_result)

      if @test_message_result.success?
        redirect_to manager_standup_chat_setup_path(@standup, test_message_sent: "1"), status: :see_other
      else
        load_chat_setup
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def chat_platform
      @standup.chat_platform
    end

    def load_chat_setup
      @chat_platform = chat_platform
      @integration_status = integration_service.configuration_status
      @connection_result = integration_service.connection_status
      @participants = @standup.standup_participants.order(:display_name, :platform_user_id)
      @channel_query = params[:channel_query]
      @user_query = params[:user_query]
      @channel_result = integration_service.discover_channels(query: @channel_query, include_private: current_user.admin?) if discovery_requested?("channels", @channel_query)
      @user_result = integration_service.discover_users(query: @user_query) if discovery_requested?("users", @user_query)
    end

    def audit_test_message!(result)
      metadata = {
        standup_id: @standup.id,
        platform_channel: @standup.platform_channel,
        status: result.status,
        error_code: result.error_code
      }.compact
      metadata[:"#{@standup.platform}_response"] = result.metadata if result.success? && result.metadata.present?

      audit_manager_change!(
        result.success? ? "#{@standup.platform}.test_message.send" : "#{@standup.platform}.test_message.failure",
        auditable: @standup,
        metadata: metadata
      )
    end

    def integration_service
      @integration_service ||= ChatIntegrationService.for(@standup.platform)
    end

    def user_resolver
      @user_resolver ||= ChatUserResolver.new(service: integration_service)
    end

    def discovery_requested?(type, query)
      query.present? || params[:discover] == type
    end
  end
end

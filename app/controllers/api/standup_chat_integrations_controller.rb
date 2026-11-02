module Api
  # The per-standup Slack / Microsoft Teams tab: pick the summary channel,
  # find and add people, and send a test message. Discovery runs when the
  # request asks for it with `channel_query`/`user_query` or
  # `discover=channels|users`.
  class StandupChatIntegrationsController < BaseController
    before_action :require_manager!
    before_action :set_standup

    def show
      render json: chat_setup_payload
    end

    def update_channel
      channel_id = params[:channel_id].to_s.strip
      channel_name = params[:channel_name].to_s.strip.presence

      if channel_id.blank?
        render_error("Select a #{chat_platform.label} channel or enter a channel ID.", field: :channel_id)
        return
      end

      previous_channel = @standup.platform_channel
      unless @standup.update(platform_channel: channel_id, platform_channel_name: channel_name)
        render_validation_errors(@standup.errors)
        return
      end

      audit_change!(
        "#{@standup.platform}.channel.update",
        auditable: @standup,
        metadata: { previous_channel: previous_channel, platform_channel: channel_id, channel_name: channel_name }.compact
      )

      render json: chat_setup_payload.merge(notice: "#{chat_platform.label} channel updated.")
    end

    def add_participant
      identifier = params[:user].presence || params[:slack_user].presence || params[:platform_user_id]
      resolved_user = user_resolver.resolve(identifier, fallback_name: params[:display_name].to_s.strip.presence)
      platform_user_id = resolved_user.platform_user_id
      display_name = resolved_user.display_name

      if platform_user_id.blank?
        render_error("Select a #{chat_platform.label} user before adding a participant.", field: :user)
        return
      end

      participant = @standup.standup_participants.find_or_initialize_by(platform_user_id: platform_user_id)
      participant.assign_attributes(display_name: display_name, active: true)
      participant.cached_timezone ||= resolved_user.cached_timezone
      participant.avatar_url = resolved_user.avatar_url if resolved_user.avatar_url.present?

      if participant.save
        audit_change!(
          "#{@standup.platform}.participant.add",
          auditable: participant,
          metadata: { standup_id: @standup.id, platform_user_id: participant.platform_user_id, display_name: display_name }
        )
        render json: chat_setup_payload.merge(participant: ParticipantSerializer.new(participant).as_json, notice: "Participant added.")
      else
        render_validation_errors(participant.errors)
      end
    rescue ChatUserResolver::ResolutionError => error
      render_error(error.message, field: :user)
    end

    def remove_participant
      participant = @standup.standup_participants.find(params[:participant_id])
      metadata = { standup_id: @standup.id, platform_user_id: participant.platform_user_id, display_name: participant.display_name }
      participant.destroy!
      audit_change!("#{@standup.platform}.participant.remove", auditable: participant, metadata: metadata)

      render json: chat_setup_payload.merge(notice: "Participant removed.")
    end

    def test_message
      result = integration_service.test_message(@standup)
      audit_test_message!(result)
      test_message = ChatResultSerializer.new(result).as_json

      if result.success?
        render json: chat_setup_payload.merge(test_message: test_message, notice: "Test standup message sent.")
      else
        render json: { error: result.message, errors: [ result.message ], test_message: test_message }, status: :unprocessable_entity
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

    def chat_setup_payload
      platform = @standup.platform
      channel_query = params[:channel_query].presence
      user_query = params[:user_query].presence
      channel_result = integration_service.discover_channels(query: channel_query, include_private: principal.admin?) if discovery_requested?("channels", channel_query)
      user_result = integration_service.discover_users(query: user_query) if discovery_requested?("users", user_query)

      {
        standup: StandupSerializer.new(@standup, include_counts: true).as_json,
        platform: { key: platform, label: chat_platform.label, icon: PlatformSerializer::ICONS.fetch(platform.to_sym, "hash") },
        channel: {
          platform_channel: @standup.platform_channel,
          platform_channel_name: @standup.platform_channel_name,
          channel_reference: @standup.channel_reference
        },
        copy: {
          channel_id_placeholder: PlatformSerializer.copy_for(platform, :channel_id_placeholder),
          channel_search_placeholder: PlatformSerializer.copy_for(platform, :channel_search_placeholder),
          user_search_placeholder: PlatformSerializer.copy_for(platform, :user_search_placeholder),
          user_placeholder: PlatformSerializer.copy_for(platform, :user_placeholder)
        },
        integration_status: ChatStatusSerializer.new(
          integration_service.configuration_status,
          connection_result: integration_service.connection_status,
          platform: platform
        ).as_json,
        participants: @standup.standup_participants.order(:display_name, :platform_user_id).map { |participant| ParticipantSerializer.new(participant).as_json },
        channel_query: channel_query,
        user_query: user_query,
        channel_result: ChatResultSerializer.new(channel_result, kind: :channels).as_json,
        user_result: ChatResultSerializer.new(user_result, kind: :users).as_json
      }
    end

    def render_error(message, field: nil)
      payload = { error: message, errors: [ message ] }
      payload[:field_errors] = { field.to_s => [ message ] } if field
      render json: payload, status: :unprocessable_entity
    end

    def audit_test_message!(result)
      metadata = {
        standup_id: @standup.id,
        platform_channel: @standup.platform_channel,
        status: result.status,
        error_code: result.error_code
      }.compact
      metadata[:"#{@standup.platform}_response"] = result.metadata if result.success? && result.metadata.present?

      audit_change!(
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

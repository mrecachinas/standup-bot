module Api
  # The per-standup Slack / Microsoft Teams tab: pick the summary channel and
  # send a test message. Channel discovery runs when the request asks for it
  # with `channel_query` or `discover=channels`. People are managed on the
  # Participants tab (StandupParticipantsController).
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
      channel_result = integration_service.discover_channels(query: channel_query, include_private: principal.admin?) if channel_query.present? || params[:discover] == "channels"

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
          channel_search_placeholder: PlatformSerializer.copy_for(platform, :channel_search_placeholder)
        },
        integration_status: ChatStatusSerializer.new(
          integration_service.configuration_status,
          connection_result: integration_service.connection_status,
          platform: platform
        ).as_json,
        channel_query: channel_query,
        channel_result: ChatResultSerializer.new(channel_result, kind: :channels).as_json
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
  end
end

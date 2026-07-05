module Manager
  class StandupSlackIntegrationsController < ApplicationController
    before_action :set_standup

    def show
      load_slack_setup
    end

    def update_channel
      channel_id = params[:channel_id].to_s.strip
      channel_name = params[:channel_name].to_s.strip.presence

      if channel_id.blank?
        @channel_update_error = "Select a Slack channel or enter a channel ID."
        load_slack_setup
        render :show, status: :unprocessable_entity
        return
      end

      previous_channel = @standup.slack_channel
      @standup.update!(slack_channel: channel_id)
      audit_manager_change!(
        "slack.channel.update",
        auditable: @standup,
        metadata: { previous_channel: previous_channel, slack_channel: channel_id, channel_name: channel_name }.compact
      )

      redirect_to manager_standup_slack_setup_path(@standup, channel_updated: "1"), status: :see_other
    end

    def add_participant
      resolved_user = resolve_slack_user(params[:slack_user].presence || params[:slack_id], fallback_name: params[:slack_name])
      slack_id = resolved_user.slack_id
      slack_name = resolved_user.slack_name

      if slack_id.blank?
        @participant_error = "Select a Slack user before adding a participant."
        load_slack_setup
        render :show, status: :unprocessable_entity
        return
      end

      participant = @standup.standup_participants.find_or_initialize_by(slack_id: slack_id)
      participant.assign_attributes(slack_name: slack_name, active: true)

      if participant.save
        audit_manager_change!(
          "slack.participant.add",
          auditable: participant,
          metadata: { standup_id: @standup.id, slack_id: slack_id, slack_name: slack_name }
        )
        redirect_to manager_standup_slack_setup_path(@standup, participant_added: "1"), status: :see_other
      else
        @participant_error = participant.errors.full_messages.to_sentence
        load_slack_setup
        render :show, status: :unprocessable_entity
      end
    rescue SlackUserResolver::ResolutionError => error
      @participant_error = error.message
      load_slack_setup
      render :show, status: :unprocessable_entity
    end

    def remove_participant
      participant = @standup.standup_participants.find(params[:participant_id])
      metadata = { standup_id: @standup.id, slack_id: participant.slack_id, slack_name: participant.slack_name }
      participant.destroy!
      audit_manager_change!("slack.participant.remove", auditable: participant, metadata: metadata)

      redirect_to manager_standup_slack_setup_path(@standup, participant_removed: "1"), status: :see_other
    end

    def test_message
      @test_message_result = slack_integration_service.test_message(@standup)
      audit_test_message!(@test_message_result)

      if @test_message_result.success?
        redirect_to manager_standup_slack_setup_path(@standup, test_message_sent: "1"), status: :see_other
      else
        load_slack_setup
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def load_slack_setup
      @slack_integration_status = slack_integration_service.configuration_status
      @connection_result = slack_integration_service.connection_status
      @participants = @standup.standup_participants.order(:slack_name, :slack_id)
      @channel_query = params[:channel_query]
      @user_query = params[:user_query]
      @channel_result = slack_integration_service.discover_channels(query: @channel_query) if discovery_requested?("channels", @channel_query)
      @user_result = slack_integration_service.discover_users(query: @user_query) if discovery_requested?("users", @user_query)
    end

    def audit_test_message!(result)
      metadata = {
        standup_id: @standup.id,
        slack_channel: @standup.slack_channel,
        status: result.status,
        error_code: result.error_code
      }.compact
      metadata[:slack_response] = result.metadata if result.success? && result.metadata.present?

      audit_manager_change!(
        result.success? ? "slack.test_message.send" : "slack.test_message.failure",
        auditable: @standup,
        metadata: metadata
      )
    end

    def slack_integration_service
      @slack_integration_service ||= SlackIntegrationService.new
    end

    def resolve_slack_user(identifier, fallback_name:)
      slack_user_resolver.resolve(identifier, fallback_name: fallback_name.to_s.strip.presence)
    end

    def slack_user_resolver
      @slack_user_resolver ||= SlackUserResolver.new(service: slack_integration_service)
    end

    def discovery_requested?(type, query)
      query.present? || params[:discover] == type
    end
  end
end

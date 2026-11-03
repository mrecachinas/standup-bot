# Handles Slack events, slash commands, and interactions the same way whether
# they arrive as signed HTTP requests or over a Socket Mode connection.
# Responses are plain hashes the caller sends back however its transport needs.
class SlackInbound
  # Allow deeper nested parameters for message_changed events.
  EVENT_FIELDS = [
    :type, :user, :text, :channel, :ts, :subtype,
    {
      message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ],
      previous_message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ]
    }
  ].freeze
  # Socket Mode routes by command name; HTTP routes by request URL.
  COMMANDS = { "/standup" => :standup, "/standup-status" => :standup_status }.freeze

  Response = Struct.new(:body, :status, keyword_init: true)

  class << self
    def enqueue_event(event)
      event = ActionController::Parameters.new(event) unless event.is_a?(ActionController::Parameters)
      event = event.permit(*EVENT_FIELDS)

      user_id = event[:user] || event.dig(:message, :user)
      Rails.logger.info "Received Slack event=#{event[:type]} subtype=#{event[:subtype]} from user=#{user_id} in channel=#{event[:channel]}"

      SlackEventProcessorJob.perform_later(event.to_h)
    end

    def slash_command(command, user_id:, text: nil)
      return ephemeral("Missing Slack user id.", status: :bad_request) if user_id.blank?

      handler = StandupCommandHandler.new(chat: chat, user_id: user_id)
      reply = command.to_sym == :standup_status ? handler.status : handler.run(text)
      blocks = chat.reply_blocks(reply)
      return ephemeral(reply.text, status: reply.status) unless blocks

      Response.new(body: { response_type: "ephemeral", text: reply.text, blocks: blocks }, status: :ok)
    end

    # Returns a Response to show the user, or nil when there's nothing to say.
    def interaction(payload)
      case payload["type"]
      when "block_actions"
        block_actions(payload)
      when "view_submission"
        nil
      else
        Rails.logger.info "Ignoring unsupported Slack interaction type=#{payload['type']}"
        nil
      end
    end

    private

    def block_actions(payload)
      action = Array(payload["actions"]).first
      return interaction_reply("No Slack action was provided.") if action.blank?

      handler = StandupCommandHandler.new(chat: chat, user_id: payload.dig("user", "id"))
      standup_id = action.dig("selected_option", "value") || action["value"]

      case action["action_id"]
      when "standup_selection"
        interaction_reply(handler.report_selected(standup_id).text)
      when "standup_start_selection"
        interaction_reply(handler.start_selected(standup_id).text)
      when StandupCommandHandler::RESTART_ACTION_ID
        interaction_reply(handler.restart(standup_id).text)
      else
        Rails.logger.info "Ignoring unsupported Slack action_id=#{action['action_id']}"
        interaction_reply("That Slack action is not supported yet.")
      end
    end

    def interaction_reply(text)
      Response.new(body: { response_type: "ephemeral", replace_original: false, text: text }, status: :ok)
    end

    def ephemeral(text, status: :ok)
      Response.new(body: { response_type: "ephemeral", text: text }, status: status)
    end

    def chat
      ChatPlatform.for(:slack)
    end
  end
end

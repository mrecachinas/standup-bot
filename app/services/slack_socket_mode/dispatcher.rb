module SlackSocketMode
  # Turns a Socket Mode envelope into the same work the HTTP controllers do,
  # and acknowledges it. Slack redelivers envelopes that aren't acked within
  # 3 seconds.
  class Dispatcher
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    # Yields the ack hash to send back over the socket. Events and clicks are
    # acked only after they're queued, so Slack redelivers them if that fails
    # and they aren't lost if the process stops after acking.
    def call(envelope, &ack)
      payload = envelope["payload"] || {}
      ack_with = ->(response = nil) { ack.call({ envelope_id: envelope["envelope_id"], payload: response }.compact) }

      case envelope["type"]
      when "events_api"
        handle_event(payload)
        ack_with.call
      when "slash_commands"
        ack_with.call(slash_command_body(payload))
      when "interactive"
        SlackInteractionJob.perform_later(payload)
        ack_with.call
      else
        @logger.info "Ignoring unsupported Slack Socket Mode envelope type=#{envelope['type']}"
        ack_with.call
      end
    end

    private

    def handle_event(payload)
      return unless payload["type"] == "event_callback" && payload["event"].is_a?(Hash)

      SlackInbound.enqueue_event(payload["event"])
    end

    def slash_command_body(payload)
      command = SlackInbound::COMMANDS[payload["command"]]
      unless command
        @logger.info "Ignoring unsupported Slack slash command=#{payload['command']}"
        return { response_type: "ephemeral", text: "That command is not supported." }
      end

      SlackInbound.slash_command(command, user_id: payload["user_id"], text: payload["text"]).body
    rescue StandardError => error
      @logger.error "Slack slash command #{payload['command']} failed: #{error.class}: #{error.message}"
      { response_type: "ephemeral", text: "Sorry, something went wrong handling that command." }
    end
  end
end

module SlackSocketMode
  # Turns a Socket Mode envelope into the same work the HTTP controllers do,
  # and acknowledges it. Slack redelivers envelopes that aren't acked within
  # 3 seconds.
  class Dispatcher
    RESPONSE_URL_HOST = /\A(?:[a-z0-9-]+\.)*slack\.com\z/

    def initialize(http: Faraday.new(request: { timeout: 10, open_timeout: 5 }), logger: Rails.logger)
      @http = http
      @logger = logger
    end

    # Yields the ack hash to send back over the socket. Events are acked only
    # after they're enqueued, so Slack redelivers them if that fails.
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
        ack_with.call
        handle_interaction(payload)
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

    # Unlike HTTP, Socket Mode ignores interaction responses in the ack, so
    # replies go to the interaction's response_url.
    def handle_interaction(payload)
      response = SlackInbound.interaction(payload)
      return unless response

      url = payload["response_url"]
      unless trusted_response_url?(url)
        @logger.warn "Slack interaction has no usable response_url; dropping reply"
        return
      end

      @http.post(url, response.body.to_json, "Content-Type" => "application/json")
    rescue Faraday::Error => error
      @logger.warn "Couldn't post Slack interaction reply: #{error.class}"
    end

    def trusted_response_url?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTPS) && RESPONSE_URL_HOST.match?(uri.host.to_s)
    rescue URI::InvalidURIError
      false
    end
  end
end

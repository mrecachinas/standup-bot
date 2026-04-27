# frozen_string_literal: true

require "json"
require Rails.root.join("app/services/slack_signature_verifier")

class Rack::Attack
  SLACK_PATHS = %w[
    /slack/events
    /slack/interactions
    /slack/install
    /slack/commands/standup
    /slack/commands/standup-status
  ].freeze

  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new if Rails.env.test?

  throttle("slack/ip", limit: 120, period: 1.minute) do |request|
    request.ip if slack_request?(request)
  end

  throttle("slack/user", limit: 30, period: 1.minute) do |request|
    slack_user_id(request) if slack_request?(request)
  end

  throttle("slack/event_replay", limit: 1, period: ::SlackSignatureVerifier::MAX_TIMESTAMP_AGE_SECONDS) do |request|
    slack_event_id(request) if request.post? && request.path == "/slack/events"
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period].to_i
    retry_after = 60 unless retry_after.positive?

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      },
      [ { error: "rate_limited" }.to_json ]
    ]
  end

  class << self
    private

    def slack_request?(request)
      request.post? && SLACK_PATHS.include?(request.path)
    end

    def slack_user_id(request)
      case request.path
      when "/slack/events"
        body = parsed_json_body(request)
        body.dig("event", "user") || body.dig("event", "message", "user")
      when "/slack/interactions"
        interaction_payload(request).dig("user", "id")
      when "/slack/install"
        request.ip
      when "/slack/commands/standup", "/slack/commands/standup-status"
        form_body(request)["user_id"]
      end
    end

    def slack_event_id(request)
      parsed_json_body(request)["event_id"]
    end

    def parsed_json_body(request)
      return {} unless request.media_type == "application/json"

      JSON.parse(request_body(request))
    rescue JSON::ParserError
      {}
    end

    def interaction_payload(request)
      params = form_body(request)
      payload = params["payload"]
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError
      {}
    end

    def request_body(request)
      body = request.body.read
      request.body.rewind
      body
    end

    def form_body(request)
      Rack::Utils.parse_nested_query(request_body(request))
    end
  end
end

Rails.application.config.middleware.use Rack::Attack

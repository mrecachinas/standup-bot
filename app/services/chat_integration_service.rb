# Console-facing checks and discovery for a chat platform: credentials,
# connection, channel and user discovery, resolving people, and test messages.
# Subclasses describe their platform's credentials and error codes.
class ChatIntegrationService
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 200

  # { key:, label:, env:, required: } for each credential, in display order.
  CREDENTIALS = [].freeze
  # Credentials the platform API calls need.
  API_CREDENTIALS = [].freeze

  Result = Struct.new(:status, :records, :metadata, :message, :action, :error_code, keyword_init: true) do
    def success?
      status == "ok"
    end
  end

  SERVICES = { slack: "SlackIntegrationService", teams: "TeamsIntegrationService" }.freeze

  def self.for(platform)
    SERVICES.fetch(ChatPlatform.key_for(platform)).constantize.new
  end

  def initialize(client:, config:)
    @client = client
    @config = config || {}
  end

  def platform
    client.key
  end

  def label
    client.label
  end

  def configuration_status
    credentials = credential_definitions.to_h do |credential|
      [ credential[:key], credential_status(credential[:key], credential[:label], required: credential[:required]) ]
    end
    ready = credentials.values.select { |credential| credential[:required] }.all? { |credential| credential[:configured] }
    installed = self.class::API_CREDENTIALS.all? { |key| configured?(key) }

    {
      platform: platform.to_s,
      label: label,
      status: ready ? "ok" : "warn",
      configured: ready,
      installation: {
        status: installed ? "configured" : "missing",
        message: installed ? installed_message : missing_installation_message
      },
      credentials: credentials,
      health: HealthCheckService.platform_status(platform)
    }
  end

  def connection_status
    return missing_api_config_result if missing_api_config_result

    response = client.connection_status
    Result.new(
      status: "ok",
      message: "#{label} API authentication succeeded.",
      metadata: response.slice("team", "team_id", "user", "user_id", "bot_id", "url", "app_id")
    )
  rescue StandardError => error
    failure_result(error, "validate the #{label} API connection")
  end

  def discover_channels(query: nil, limit: DEFAULT_LIMIT, include_private: true)
    return missing_api_config_result if missing_api_config_result

    records = client.list_channels(query: query, limit: normalized_limit(limit))
    records = records.reject { |record| record["is_private"] } unless include_private
    Result.new(status: "ok", records: records, message: "Found #{records.size} #{label} channel(s).")
  rescue StandardError => error
    failure_result(error, "discover #{label} channels")
  end

  def discover_users(query: nil, limit: DEFAULT_LIMIT)
    return missing_api_config_result if missing_api_config_result

    records = client.search_users(query: query, limit: normalized_limit(limit))
    Result.new(status: "ok", records: records, message: "Found #{records.size} #{label} user(s).")
  rescue StandardError => error
    failure_result(error, "discover #{label} users")
  end

  def resolve_user(identifier, limit: MAX_LIMIT)
    lookup = normalize_user_lookup(identifier)
    return Result.new(status: "error", message: "Enter #{user_lookup_hint}.", error_code: "missing_user") if lookup.blank?

    if user_id_like?(lookup)
      user_id = client.normalize_user_id(lookup)
      return Result.new(status: "ok", records: [ { "id" => user_id, "label" => user_id } ], message: "#{label} user ID accepted.")
    end

    return missing_api_config_result if missing_api_config_result

    records = client.search_users(query: lookup, limit: normalized_limit(limit))
    matches = exact_user_matches(records, lookup)
    matches = records if matches.empty? && records.one?

    case matches.size
    when 1
      Result.new(status: "ok", records: [ matches.first ], message: "Resolved #{label} user.")
    when 0
      Result.new(
        status: "error",
        message: "No #{label} user matched \"#{lookup}\".",
        action: "Use #{user_lookup_hint}.",
        error_code: "user_not_found"
      )
    else
      Result.new(
        status: "error",
        records: matches,
        message: "\"#{lookup}\" matched multiple #{label} users.",
        action: "Use a more specific name or pick the user from #{label} discovery.",
        error_code: "ambiguous_user"
      )
    end
  rescue StandardError => error
    failure_result(error, "resolve #{label} user")
  end

  def test_message(standup)
    return missing_api_config_result if missing_api_config_result

    if standup.platform_channel.blank?
      return Result.new(
        status: "error",
        message: "The standup does not have a #{label} channel configured.",
        action: "Select a #{label} channel before sending a test message.",
        error_code: "missing_channel"
      )
    end

    message = client.send_message(standup.platform_channel, test_message_text(standup))
    Result.new(
      status: "ok",
      message: "#{label} accepted the test standup message.",
      metadata: { "channel" => message&.channel, "ts" => message&.id }.compact
    )
  rescue StandardError => error
    failure_result(error, "send a test standup message")
  end

  private

  attr_reader :client, :config

  # The credentials to show, in display order. Subclasses can narrow this when
  # some only apply to certain configurations.
  def credential_definitions
    self.class::CREDENTIALS
  end

  def installed_message
    "#{label} credentials are configured."
  end

  def missing_installation_message
    "Set #{self.class::API_CREDENTIALS.map { |key| env_for(key) }.join(', ')} before using #{label} actions."
  end

  def user_lookup_hint
    "a #{label} name, email, or user ID"
  end

  def user_id_like?(lookup)
    client.looks_like_user_id?(lookup)
  end

  def credential_status(key, credential_label, required:)
    configured = configured?(key)
    {
      label: credential_label,
      configured: configured,
      required: required,
      message: credential_message(credential_label, configured, required)
    }
  end

  def credential_message(credential_label, configured, required)
    return "#{credential_label} is configured." if configured
    return "#{credential_label} is required for #{label} integration." if required

    "#{credential_label} is optional for this workflow and is not configured."
  end

  def configured?(key)
    config_value(key).present?
  end

  def config_value(key)
    if config.respond_to?(:[])
      config[key] || config[key.to_s]
    elsif config.respond_to?(key)
      config.public_send(key)
    end
  end

  def env_for(key)
    self.class::CREDENTIALS.find { |credential| credential[:key] == key }&.dig(:env) || key.to_s.upcase
  end

  def missing_api_config_result
    missing = self.class::API_CREDENTIALS.find { |key| !configured?(key) }
    return unless missing

    Result.new(
      status: "error",
      message: "#{label} #{missing.to_s.humanize.downcase} is not configured.",
      action: "Set #{env_for(missing)} and restart the app.",
      error_code: "missing_#{missing}"
    )
  end

  def normalized_limit(limit)
    limit.to_i.clamp(1, MAX_LIMIT)
  end

  def normalize_user_lookup(identifier)
    identifier.to_s.strip.delete_prefix("@")
  end

  def exact_user_matches(records, lookup)
    lookup_key = normalized_match_key(lookup)
    Array(records).select do |record|
      user_match_values(record).any? { |value| normalized_match_key(value) == lookup_key }
    end
  end

  def user_match_values(record)
    %w[id name display_name real_name email label].filter_map { |key| record[key].presence }
  end

  def normalized_match_key(value)
    value.to_s.strip.delete_prefix("@").downcase
  end

  def test_message_text(standup)
    <<~TEXT.squish
      This is a test standup message for #{standup.name} from Standup Bot.
      If you can read this, the configured #{label} channel is reachable.
    TEXT
  end

  def failure_result(error, operation)
    error_code = error_code_for(error)
    Result.new(
      status: "error",
      message: error_message_for(error_code, error, operation),
      action: action_for(error_code),
      error_code: error_code
    )
  end

  def error_code_for(error)
    return "too_many_requests" if error.is_a?(ChatPlatform::RateLimitedError)

    error.class.name.demodulize.underscore
  end

  def error_message_for(error_code, error, operation)
    return "#{label} API rate limit was reached." if error_code == "too_many_requests"

    "#{label} API could not #{operation}: #{sanitized_error_message(error)}"
  end

  def action_for(error_code)
    return "Wait for #{label}'s rate limit window to reset, then retry." if error_code == "too_many_requests"

    "Review #{label} app configuration and retry."
  end

  def sanitized_error_message(error)
    message = error.message.to_s.presence || error.class.name
    secret_values.reduce(message) { |sanitized, secret| sanitized.gsub(secret, "[FILTERED]") }
  end

  def secret_values
    self.class::CREDENTIALS.select { |credential| credential[:secret] }.filter_map { |credential| config_value(credential[:key]).presence }
  end
end

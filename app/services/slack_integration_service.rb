class SlackIntegrationService
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 200
  SECRET_KEYS = %i[bot_token signing_secret client_secret].freeze

  Result = Struct.new(:status, :records, :metadata, :message, :action, :error_code, keyword_init: true) do
    def success?
      status == "ok"
    end
  end

  def initialize(client: SlackClient.instance, config: Rails.application.config.slack)
    @client = client
    @config = config || {}
  end

  def configuration_status
    credentials = {
      bot_token: credential_status(:bot_token, "Bot token", required: true),
      signing_secret: credential_status(:signing_secret, "Signing secret", required: true),
      client_id: credential_status(:client_id, "Client ID", required: false),
      client_secret: credential_status(:client_secret, "Client secret", required: false)
    }
    ready = credentials[:bot_token][:configured] && credentials[:signing_secret][:configured]

    {
      status: ready ? "ok" : "warn",
      configured: ready,
      installation: {
        status: credentials[:bot_token][:configured] ? "configured" : "missing",
        message: credentials[:bot_token][:configured] ?
          "Slack app bot token is configured." :
          "Install the Slack app and set SLACK_BOT_TOKEN before using Slack actions."
      },
      credentials: credentials,
      health: HealthCheckService.slack_status
    }
  end

  def connection_status
    return missing_config_result(:bot_token) unless configured?(:bot_token)

    response = client.auth_test
    Result.new(
      status: "ok",
      message: "Slack API authentication succeeded.",
      metadata: response.slice("team", "team_id", "user", "user_id", "bot_id", "url")
    )
  rescue StandardError => error
    failure_result(error, "validate the Slack API connection")
  end

  def discover_channels(query: nil, limit: DEFAULT_LIMIT)
    return missing_config_result(:bot_token) unless configured?(:bot_token)

    records = client.list_channels(query: query, limit: normalized_limit(limit))
    Result.new(status: "ok", records: records, message: "Found #{records.size} Slack channel(s).")
  rescue StandardError => error
    failure_result(error, "discover Slack channels")
  end

  def discover_users(query: nil, limit: DEFAULT_LIMIT)
    return missing_config_result(:bot_token) unless configured?(:bot_token)

    records = client.list_users(query: query, limit: normalized_limit(limit))
    Result.new(status: "ok", records: records, message: "Found #{records.size} Slack user(s).")
  rescue StandardError => error
    failure_result(error, "discover Slack users")
  end

  def resolve_user(identifier, limit: MAX_LIMIT)
    lookup = normalize_user_lookup(identifier)
    return Result.new(status: "error", message: "Enter a Slack username, display name, or user ID.", error_code: "missing_user") if lookup.blank?

    if slack_user_id?(lookup)
      return Result.new(status: "ok", records: [ { "id" => lookup.upcase, "label" => lookup.upcase } ], message: "Slack user ID accepted.")
    end

    return missing_config_result(:bot_token) unless configured?(:bot_token)

    records = client.list_users(query: lookup, limit: normalized_limit(limit))
    matches = exact_user_matches(records, lookup)
    matches = records if matches.empty? && records.one?

    case matches.size
    when 1
      Result.new(status: "ok", records: [ matches.first ], message: "Resolved Slack user.")
    when 0
      Result.new(
        status: "error",
        message: "No Slack user matched \"#{lookup}\".",
        action: "Use a Slack @username, display name, real name, or paste a user mention from Slack.",
        error_code: "user_not_found"
      )
    else
      Result.new(
        status: "error",
        records: matches,
        message: "\"#{lookup}\" matched multiple Slack users.",
        action: "Use a more specific username or pick the user from Slack discovery.",
        error_code: "ambiguous_user"
      )
    end
  rescue StandardError => error
    failure_result(error, "resolve Slack user")
  end

  def test_message(standup)
    return missing_config_result(:bot_token) unless configured?(:bot_token)

    if standup.slack_channel.blank?
      return Result.new(
        status: "error",
        message: "The standup does not have a Slack channel configured.",
        action: "Select a Slack channel before sending a test message.",
        error_code: "missing_channel"
      )
    end

    response = client.send_message(standup.slack_channel, test_message_text(standup))
    Result.new(
      status: "ok",
      message: "Slack accepted the test standup message.",
      metadata: response.slice("channel", "ts")
    )
  rescue StandardError => error
    failure_result(error, "send a test standup message")
  end

  private

  attr_reader :client, :config

  def credential_status(key, label, required:)
    configured = configured?(key)
    {
      label: label,
      configured: configured,
      required: required,
      message: credential_message(label, configured, required)
    }
  end

  def credential_message(label, configured, required)
    return "#{label} is configured." if configured
    return "#{label} is required for Slack integration." if required

    "#{label} is optional for this workflow and is not configured."
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

  def missing_config_result(key)
    Result.new(
      status: "error",
      message: "Slack #{key.to_s.humanize.downcase} is not configured.",
      action: "Set #{key.to_s.upcase.prepend('SLACK_')} and restart the app.",
      error_code: "missing_#{key}"
    )
  end

  def normalized_limit(limit)
    limit.to_i.clamp(1, MAX_LIMIT)
  end

  def normalize_user_lookup(identifier)
    identifier.to_s.strip.delete_prefix("@")
  end

  def slack_user_id?(identifier)
    value = identifier.to_s
    normalized = value.upcase
    (value == normalized && normalized.match?(StandupParticipant::SLACK_USER_ID_PATTERN)) ||
      normalized.match?(/\A[UW][A-Z0-9]*\d[A-Z0-9]*\z/)
  end

  def exact_user_matches(records, lookup)
    lookup_key = normalized_match_key(lookup)
    Array(records).select do |record|
      user_match_values(record).any? { |value| normalized_match_key(value) == lookup_key }
    end
  end

  def user_match_values(record)
    %w[id name display_name real_name label].filter_map { |key| record[key].presence }
  end

  def normalized_match_key(value)
    value.to_s.strip.delete_prefix("@").downcase
  end

  def test_message_text(standup)
    <<~TEXT.squish
      This is a test standup message for #{standup.name} from Standup Bot.
      If you can read this, the configured Slack channel is reachable.
    TEXT
  end

  def failure_result(error, operation)
    error_code = slack_error_code(error)
    Result.new(
      status: "error",
      message: error_message_for(error_code, error, operation),
      action: action_for(error_code),
      error_code: error_code
    )
  end

  def slack_error_code(error)
    return "too_many_requests" if defined?(Slack::Web::Api::Errors::TooManyRequestsError) && error.is_a?(Slack::Web::Api::Errors::TooManyRequestsError)

    message = sanitized_error_message(error)
    return message if message.match?(/\A[a-z][a-z0-9_]+\z/)

    error.class.name.demodulize.underscore
  end

  def error_message_for(error_code, error, operation)
    case error_code
    when "invalid_auth", "not_authed", "account_inactive"
      "Slack rejected the configured bot token (#{error_code})."
    when "missing_scope"
      "Slack app is missing a required OAuth scope."
    when "channel_not_found"
      "Slack could not find the configured channel."
    when "not_in_channel"
      "Slack bot is not a member of the configured channel."
    when "too_many_requests"
      "Slack API rate limit was reached."
    else
      "Slack API could not #{operation}: #{sanitized_error_message(error)}"
    end
  end

  def action_for(error_code)
    case error_code
    when "invalid_auth", "not_authed", "account_inactive"
      "Reinstall the Slack app or update SLACK_BOT_TOKEN."
    when "missing_scope"
      "Add the required Slack scopes, reinstall the app, then retry."
    when "channel_not_found"
      "Select an existing Slack channel from discovery and save it."
    when "not_in_channel"
      "Invite the Slack bot to the channel, then retry."
    when "too_many_requests"
      "Wait for Slack's rate limit window to reset, then retry."
    else
      "Review Slack app configuration and retry."
    end
  end

  def sanitized_error_message(error)
    message = error.message.to_s.presence || error.class.name
    configured_secret_values.reduce(message) do |sanitized, secret|
      sanitized.gsub(secret, "[FILTERED]")
    end.gsub(/xox[baprs]-[A-Za-z0-9-]+/, "[FILTERED]")
  end

  def configured_secret_values
    SECRET_KEYS.filter_map { |key| config_value(key).presence }
  end
end

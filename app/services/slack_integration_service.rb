class SlackIntegrationService < ChatIntegrationService
  CREDENTIALS = [
    { key: :bot_token, label: "Bot token", env: "SLACK_BOT_TOKEN", required: true, secret: true },
    { key: :signing_secret, label: "Signing secret", env: "SLACK_SIGNING_SECRET", required: true, secret: true, connection_mode: "http" },
    { key: :app_token, label: "App-level token", env: "SLACK_APP_TOKEN", required: true, secret: true, connection_mode: "socket" },
    { key: :client_id, label: "Client ID", env: "SLACK_CLIENT_ID", required: false },
    { key: :client_secret, label: "Client secret", env: "SLACK_CLIENT_SECRET", required: false, secret: true }
  ].freeze
  API_CREDENTIALS = %i[bot_token].freeze

  def initialize(client: ChatPlatform.for(:slack), config: Rails.application.config.slack)
    super
  end

  private

  # The signing secret is only used for HTTP request URLs and the app-level
  # token only for Socket Mode, so show whichever SLACK_CONNECTION_MODE needs.
  def credential_definitions
    mode = SlackConfig.connection_mode(config)
    CREDENTIALS.select { |credential| credential[:connection_mode].nil? || credential[:connection_mode] == mode }
  end

  def installed_message
    "Slack app bot token is configured. Receiving Slack traffic over #{SlackConfig.connection_mode_label(config)}."
  end

  def missing_installation_message
    "Install the Slack app and set SLACK_BOT_TOKEN before using Slack actions."
  end

  def user_lookup_hint
    "a Slack username, display name, or user ID"
  end

  def error_code_for(error)
    return "too_many_requests" if error.is_a?(Slack::Web::Api::Errors::TooManyRequestsError)

    message = sanitized_error_message(error)
    return message if message.match?(/\A[a-z][a-z0-9_]+\z/)

    super
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
    else
      super
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
    else
      super
    end
  end

  def sanitized_error_message(error)
    super.gsub(/(?:xox[baprs]|xapp)-[A-Za-z0-9-]+/, "[FILTERED]")
  end
end

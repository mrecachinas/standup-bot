# Reads config/slack.yml (Rails.application.config.slack).
#
# Slack can deliver events, slash commands, and interactions two ways:
# - "http" (default): Slack POSTs to the app's public request URLs, verified
#   with the signing secret.
# - "socket": the app opens an outbound WebSocket to Slack using an app-level
#   token (xapp-...), so no public URL is needed. See SlackSocketMode::Client.
module SlackConfig
  CONNECTION_MODES = %w[http socket].freeze
  DEFAULT_CONNECTION_MODE = "http"

  module_function

  def value(key, config = Rails.application.config.slack)
    config ||= {}
    if config.respond_to?(:[])
      (config[key] || config[key.to_s]).presence
    elsif config.respond_to?(key)
      config.public_send(key).presence
    end
  end

  def bot_token(config = Rails.application.config.slack) = value(:bot_token, config)
  def signing_secret(config = Rails.application.config.slack) = value(:signing_secret, config)
  def app_token(config = Rails.application.config.slack) = value(:app_token, config)

  def connection_mode(config = Rails.application.config.slack)
    mode = value(:connection_mode, config).to_s.strip.downcase
    CONNECTION_MODES.include?(mode) ? mode : DEFAULT_CONNECTION_MODE
  end

  def socket_mode?(config = Rails.application.config.slack)
    connection_mode(config) == "socket"
  end

  # The credential Slack needs to deliver inbound traffic in the current mode.
  def inbound_credential_key(config = Rails.application.config.slack)
    socket_mode?(config) ? :app_token : :signing_secret
  end

  def configured?(config = Rails.application.config.slack)
    bot_token(config).present? && value(inbound_credential_key(config), config).present?
  end

  def connection_mode_label(config = Rails.application.config.slack)
    socket_mode?(config) ? "Socket Mode" : "HTTP request URLs"
  end

  # Fails fast on a typo like SLACK_CONNECTION_MODE=sockets instead of quietly
  # falling back to HTTP and never receiving anything.
  def validate!(config = Rails.application.config.slack)
    mode = value(:connection_mode, config).to_s.strip.downcase
    return if mode.blank? || CONNECTION_MODES.include?(mode)

    raise ArgumentError, "SLACK_CONNECTION_MODE must be one of #{CONNECTION_MODES.join(', ')} (got #{mode.inspect})"
  end
end

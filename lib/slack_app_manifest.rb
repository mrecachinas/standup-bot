require "uri"
require "yaml"

class SlackAppManifest
  DEFAULT_APP_NAME = "Standup Bot"
  DEFAULT_DESCRIPTION = "Automates daily standups by collecting Slack DM responses and posting team summaries."
  BOT_SCOPES = %w[channels:read chat:write commands im:history im:write users:read].freeze
  # "Sign in with Slack" (OpenID Connect) for the web console.
  USER_SCOPES = %w[openid email profile].freeze

  # In Socket Mode, Slack doesn't call request URLs, so app_url is only
  # needed for "Sign in with Slack" and may be omitted.
  def initialize(app_url:, app_name: DEFAULT_APP_NAME, description: DEFAULT_DESCRIPTION, socket_mode: false)
    @socket_mode = socket_mode
    @app_url = app_url.blank? && socket_mode ? nil : normalize_app_url(app_url)
    @app_name = app_name.to_s.strip.presence || DEFAULT_APP_NAME
    @description = description.to_s.strip.presence || DEFAULT_DESCRIPTION
  end

  def to_h
    {
      "display_information" => {
        "name" => @app_name,
        "description" => @description,
        "background_color" => "#2c2d30"
      },
      "features" => {
        # Participants answer in the bot's DM, so the Messages tab must accept input.
        "app_home" => {
          "home_tab_enabled" => false,
          "messages_tab_enabled" => true,
          "messages_tab_read_only_enabled" => false
        },
        "bot_user" => {
          "display_name" => @app_name,
          "always_online" => false
        },
        "slash_commands" => slash_commands
      },
      "oauth_config" => oauth_config,
      "settings" => {
        "event_subscriptions" => request_url("/slack/events").merge("bot_events" => [ "message.im" ]),
        "interactivity" => { "is_enabled" => true }.merge(request_url("/slack/interactions")),
        "org_deploy_enabled" => false,
        "socket_mode_enabled" => @socket_mode,
        "token_rotation_enabled" => false
      }
    }
  end

  def to_yaml
    YAML.dump(to_h)
  end

  private

  def slash_commands
    [
      {
        "command" => "/standup",
        **request_url("/slack/commands/standup", key: "url"),
        "description" => "Start, skip, report, view history, and get help for standups.",
        "usage_hint" => "[start|status|skip|report|history|help]",
        "should_escape" => false
      },
      {
        "command" => "/standup-status",
        **request_url("/slack/commands/standup-status", key: "url"),
        # No usage_hint: Slack rejects manifests with an empty one.
        "description" => "Check today's standup status.",
        "should_escape" => false
      }
    ]
  end

  # Sign in with Slack needs a redirect URL, so it's left out when there isn't one.
  def oauth_config
    return { "scopes" => { "bot" => BOT_SCOPES } } if @app_url.nil?

    {
      "redirect_urls" => [ app_url_for("/auth/slack/callback") ],
      "scopes" => {
        "bot" => BOT_SCOPES,
        "user" => USER_SCOPES
      }
    }
  end

  # Socket Mode delivers everything over the WebSocket, so there are no request URLs.
  def request_url(path, key: "request_url")
    @socket_mode ? {} : { key => app_url_for(path) }
  end

  def app_url_for(path)
    "#{@app_url}#{path}"
  end

  def normalize_app_url(app_url)
    uri = URI.parse(app_url.to_s.strip)
    unless uri.is_a?(URI::HTTP) && uri.host.present?
      raise ArgumentError, "APP_URL must be an absolute http(s) URL"
    end

    uri.to_s.delete_suffix("/")
  rescue URI::InvalidURIError
    raise ArgumentError, "APP_URL must be an absolute http(s) URL"
  end
end

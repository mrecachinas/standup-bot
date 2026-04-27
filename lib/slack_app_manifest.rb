require "uri"
require "yaml"

class SlackAppManifest
  DEFAULT_APP_NAME = "Standup Bot"
  DEFAULT_DESCRIPTION = "Automates daily standups by collecting Slack DM responses and posting team summaries."
  BOT_SCOPES = %w[channels:read chat:write commands im:history im:write users:read].freeze

  def initialize(app_url:, app_name: DEFAULT_APP_NAME, description: DEFAULT_DESCRIPTION)
    @app_url = normalize_app_url(app_url)
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
        "bot_user" => {
          "display_name" => @app_name,
          "always_online" => false
        },
        "slash_commands" => slash_commands
      },
      "oauth_config" => {
        "scopes" => {
          "bot" => BOT_SCOPES
        }
      },
      "settings" => {
        "event_subscriptions" => {
          "request_url" => app_url_for("/slack/events"),
          "bot_events" => [ "message.im" ]
        },
        "interactivity" => {
          "is_enabled" => true,
          "request_url" => app_url_for("/slack/interactions")
        },
        "org_deploy_enabled" => false,
        "socket_mode_enabled" => false,
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
        "url" => app_url_for("/slack/commands/standup"),
        "description" => "Start, skip, report, view history, and get help for standups.",
        "usage_hint" => "[start|status|skip|report|history|help]",
        "should_escape" => false
      },
      {
        "command" => "/standup-status",
        "url" => app_url_for("/slack/commands/standup-status"),
        "description" => "Check today's standup status.",
        "usage_hint" => "",
        "should_escape" => false
      }
    ]
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

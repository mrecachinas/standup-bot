require "json"
require "uri"

# Builds the manifest.json for the Standup Bot Teams app. Zip it with a
# 192x192 color.png and a 32x32 outline.png to upload it (see docs/teams-setup.md).
class TeamsAppManifest
  SCHEMA_VERSION = "1.17".freeze
  DEFAULT_APP_NAME = "Standup Bot".freeze
  DEFAULT_DESCRIPTION = "Automates daily standups by collecting answers in Teams chats and posting team summaries.".freeze
  SHORT_DESCRIPTION = "Async standups: questions in chat, updates in your channel.".freeze
  GUID_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  PERSONAL_COMMANDS = [
    [ "standup", "Start a standup now" ],
    [ "standup status", "Check today's progress" ],
    [ "standup skip", "Skip remaining questions for active standups" ],
    [ "standup report", "Generate a standup report" ],
    [ "standup history", "Show recent responses" ],
    [ "skip", "Skip the current question" ],
    [ "away", "Take time away (optionally: away 3)" ],
    [ "back", "Come back from time away" ],
    [ "help", "Show what you can type here" ]
  ].freeze

  CHANNEL_COMMANDS = [
    [ "status", "Check today's progress (answered in a private chat)" ],
    [ "report", "Generate a standup report" ],
    [ "help", "Show standup commands" ]
  ].freeze

  def initialize(app_url:, app_id:, app_name: DEFAULT_APP_NAME, description: DEFAULT_DESCRIPTION, version: "1.0.0")
    @app_url = normalize_app_url(app_url)
    @app_id = app_id.to_s.strip.downcase
    raise ArgumentError, "TEAMS_APP_ID must be the bot's Microsoft app (client) ID" unless @app_id.match?(GUID_PATTERN)

    @app_name = app_name.to_s.strip.presence || DEFAULT_APP_NAME
    @description = description.to_s.strip.presence || DEFAULT_DESCRIPTION
    @version = version
  end

  def to_h
    {
      "$schema" => "https://developer.microsoft.com/en-us/json-schemas/teams/v#{SCHEMA_VERSION}/MicrosoftTeams.schema.json",
      "manifestVersion" => SCHEMA_VERSION,
      "version" => @version,
      "id" => @app_id,
      "developer" => {
        "name" => @app_name,
        "websiteUrl" => @app_url,
        "privacyUrl" => @app_url,
        "termsOfUseUrl" => @app_url
      },
      "name" => { "short" => @app_name.truncate(30), "full" => @app_name },
      "description" => { "short" => (@description.length <= 80 ? @description : SHORT_DESCRIPTION), "full" => @description },
      "icons" => { "color" => "color.png", "outline" => "outline.png" },
      "accentColor" => "#2C2D30",
      "bots" => [
        {
          "botId" => @app_id,
          "scopes" => %w[personal team groupChat],
          "supportsFiles" => false,
          "isNotificationOnly" => false,
          "commandLists" => [
            { "scopes" => [ "personal" ], "commands" => commands(PERSONAL_COMMANDS) },
            { "scopes" => %w[team groupChat], "commands" => commands(CHANNEL_COMMANDS) }
          ]
        }
      ],
      "permissions" => %w[identity messageTeamMembers],
      "validDomains" => [ URI.parse(@app_url).host ]
    }
  end

  def to_json(*)
    JSON.pretty_generate(to_h)
  end

  private

  def commands(list)
    list.map { |title, description| { "title" => title, "description" => description } }
  end

  def normalize_app_url(app_url)
    uri = URI.parse(app_url.to_s.strip)
    raise ArgumentError, "APP_URL must be an absolute https URL" unless uri.is_a?(URI::HTTPS) && uri.host.present?

    uri.to_s.delete_suffix("/")
  rescue URI::InvalidURIError
    raise ArgumentError, "APP_URL must be an absolute https URL"
  end
end

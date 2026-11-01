namespace :teams do
  desc "Print a Teams app manifest.json. Usage: APP_URL=https://your-domain.example TEAMS_APP_ID=<app id> bin/rails teams:manifest"
  task manifest: :environment do
    app_url = ENV["APP_URL"].presence
    app_id = ENV["TEAMS_APP_ID"].presence || Microsoft::Config.app_id

    abort "Set APP_URL=https://your-public-domain before running teams:manifest" if app_url.blank?
    abort "Set TEAMS_APP_ID to the bot's Microsoft app (client) ID before running teams:manifest" if app_id.blank?

    manifest = TeamsAppManifest.new(
      app_url: app_url,
      app_id: app_id,
      app_name: ENV.fetch("TEAMS_APP_NAME", TeamsAppManifest::DEFAULT_APP_NAME),
      description: ENV.fetch("TEAMS_APP_DESCRIPTION", TeamsAppManifest::DEFAULT_DESCRIPTION),
      version: ENV.fetch("TEAMS_APP_VERSION", "1.0.0")
    )

    puts manifest.to_json
  rescue ArgumentError => error
    abort error.message
  end
end

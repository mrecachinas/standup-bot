namespace :slack do
  desc "Print a Slack app manifest. Usage: APP_URL=https://your-domain.example bin/rails slack:manifest"
  task manifest: :environment do
    app_url = ENV["APP_URL"].presence || ENV["SLACK_APP_URL"].presence

    abort "Set APP_URL=https://your-public-domain before running slack:manifest" if app_url.blank?

    manifest = SlackAppManifest.new(
      app_url: app_url,
      app_name: ENV.fetch("SLACK_APP_NAME", SlackAppManifest::DEFAULT_APP_NAME),
      description: ENV.fetch("SLACK_APP_DESCRIPTION", SlackAppManifest::DEFAULT_DESCRIPTION)
    )

    puts manifest.to_yaml
  rescue ArgumentError => error
    abort error.message
  end
end

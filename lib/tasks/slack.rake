namespace :slack do
  desc "Print a Slack app manifest. Usage: APP_URL=https://your-domain.example bin/rails slack:manifest " \
       "(with SLACK_CONNECTION_MODE=socket, APP_URL is only needed for Sign in with Slack)"
  task manifest: :environment do
    app_url = ENV["APP_URL"].presence || ENV["SLACK_APP_URL"].presence
    socket_mode = SlackConfig.socket_mode?

    abort "Set APP_URL=https://your-public-domain before running slack:manifest" if app_url.blank? && !socket_mode

    manifest = SlackAppManifest.new(
      app_url: app_url,
      app_name: ENV.fetch("SLACK_APP_NAME", SlackAppManifest::DEFAULT_APP_NAME),
      description: ENV.fetch("SLACK_APP_DESCRIPTION", SlackAppManifest::DEFAULT_DESCRIPTION),
      socket_mode: socket_mode
    )

    puts manifest.to_yaml
  rescue ArgumentError => error
    abort error.message
  end

  desc "Pick up DM replies missed during an outage (longer than Slack's ~5 minutes of redeliveries) from DM history"
  task backfill_dms: :environment do
    SlackDmBackfillJob.perform_now
  end
end

require "test_helper"

class SlackAppManifestTest < ActiveSupport::TestCase
  test "builds Slack app manifest YAML with app routes and required scopes" do
    manifest = YAML.safe_load(SlackAppManifest.new(app_url: "https://standup.example.com/", app_name: "Nerdbot").to_yaml)

    assert_equal "Nerdbot", manifest.dig("display_information", "name")
    assert_equal "https://standup.example.com/slack/events",
      manifest.dig("settings", "event_subscriptions", "request_url")
    assert_equal [ "message.im" ], manifest.dig("settings", "event_subscriptions", "bot_events")
    assert_equal "https://standup.example.com/slack/interactions",
      manifest.dig("settings", "interactivity", "request_url")
    assert_equal false, manifest.dig("settings", "socket_mode_enabled")

    scopes = manifest.dig("oauth_config", "scopes", "bot")
    %w[channels:read chat:write commands im:history im:write users:read].each do |scope|
      assert_includes scopes, scope
    end

    assert_equal [ "https://standup.example.com/auth/slack/callback" ], manifest.dig("oauth_config", "redirect_urls")
    assert_equal %w[openid email profile], manifest.dig("oauth_config", "scopes", "user")

    commands = manifest.dig("features", "slash_commands")
    assert_equal "/standup", commands.first.fetch("command")
    assert_equal "https://standup.example.com/slack/commands/standup", commands.first.fetch("url")
    assert_equal "/standup-status", commands.second.fetch("command")
    assert_equal "https://standup.example.com/slack/commands/standup-status", commands.second.fetch("url")
  end

  test "socket mode manifest has no request URLs" do
    manifest = YAML.safe_load(SlackAppManifest.new(app_url: "https://standup.example.com", socket_mode: true).to_yaml)

    assert_equal true, manifest.dig("settings", "socket_mode_enabled")
    assert_equal({ "bot_events" => [ "message.im" ] }, manifest.dig("settings", "event_subscriptions"))
    assert_equal({ "is_enabled" => true }, manifest.dig("settings", "interactivity"))
    assert manifest.dig("features", "slash_commands").none? { |command| command.key?("url") }
    assert_equal [ "https://standup.example.com/auth/slack/callback" ], manifest.dig("oauth_config", "redirect_urls")
  end

  test "socket mode doesn't need an app url, but then leaves out Sign in with Slack" do
    manifest = SlackAppManifest.new(app_url: nil, socket_mode: true).to_h

    assert_equal({ "scopes" => { "bot" => SlackAppManifest::BOT_SCOPES } }, manifest["oauth_config"])
  end

  test "requires absolute http url" do
    error = assert_raises(ArgumentError) do
      SlackAppManifest.new(app_url: "localhost:3000")
    end

    assert_equal "APP_URL must be an absolute http(s) URL", error.message
  end
end

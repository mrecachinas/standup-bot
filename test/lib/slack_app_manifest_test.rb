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

  test "requires absolute http url" do
    error = assert_raises(ArgumentError) do
      SlackAppManifest.new(app_url: "localhost:3000")
    end

    assert_equal "APP_URL must be an absolute http(s) URL", error.message
  end
end

require "test_helper"

class SlackAppManifestTest < ActiveSupport::TestCase
  test "builds Slack app manifest with app routes and required scopes" do
    manifest = SlackAppManifest.new(app_url: "https://standup.example.com/", app_name: "Nerdbot").to_h

    assert_equal "Nerdbot", manifest.dig("display_information", "name")
    assert_equal "https://standup.example.com/slack/events",
      manifest.dig("settings", "event_subscriptions", "request_url")
    assert_equal [ "message.im" ], manifest.dig("settings", "event_subscriptions", "bot_events")
    assert_equal "https://standup.example.com/slack/interactions",
      manifest.dig("settings", "interactivity", "request_url")

    scopes = manifest.dig("oauth_config", "scopes", "bot")
    %w[channels:read chat:write commands im:history im:write users:read].each do |scope|
      assert_includes scopes, scope
    end

    commands = manifest.dig("features", "slash_commands")
    assert_equal "/standup", commands.first.fetch("command")
    assert_equal "https://standup.example.com/slack/commands/standup", commands.first.fetch("url")
    assert_equal "/standup-status", commands.second.fetch("command")
    assert_equal "https://standup.example.com/slack/commands/standup-status", commands.second.fetch("url")
  end

  test "renders YAML accepted by Slack manifest import" do
    yaml = SlackAppManifest.new(app_url: "https://standup.example.com").to_yaml
    parsed = YAML.safe_load(yaml)

    assert_equal "Standup Bot", parsed.dig("display_information", "name")
    assert_equal false, parsed.dig("settings", "socket_mode_enabled")
  end

  test "requires absolute http url" do
    error = assert_raises(ArgumentError) do
      SlackAppManifest.new(app_url: "localhost:3000")
    end

    assert_equal "APP_URL must be an absolute http(s) URL", error.message
  end
end

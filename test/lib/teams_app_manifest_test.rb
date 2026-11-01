require "test_helper"

class TeamsAppManifestTest < ActiveSupport::TestCase
  APP_ID = "11111111-2222-3333-4444-555555555555"

  test "builds a bot manifest for personal and team scopes" do
    manifest = JSON.parse(TeamsAppManifest.new(app_url: "https://standup.example.com/", app_id: APP_ID.upcase).to_json)

    assert_equal APP_ID, manifest["id"]
    assert_equal APP_ID, manifest.dig("bots", 0, "botId")
    assert_equal %w[personal team groupChat], manifest.dig("bots", 0, "scopes")
    assert_equal [ "standup.example.com" ], manifest["validDomains"]
    assert_includes manifest.dig("bots", 0, "commandLists", 0, "commands").map { |command| command["title"] }, "standup status"
  end

  test "requires an https app URL and a GUID app ID" do
    assert_raises(ArgumentError) { TeamsAppManifest.new(app_url: "http://standup.example.com", app_id: APP_ID) }
    assert_raises(ArgumentError) { TeamsAppManifest.new(app_url: "https://standup.example.com", app_id: "not-a-guid") }
  end
end

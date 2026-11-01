require "test_helper"
require_relative "../../support/teams_test_helper"

# The console with Microsoft Teams turned on alongside Slack.
class Manager::TeamsStandupsTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    enable_teams!
    @manager = users(:manager)
    post session_path, params: { email: @manager.email, access_token: "manager-access-token" }
    TeamsIntegrationService.any_instance.stubs(:discover_channels).returns(
      ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ])
    )
  end

  test "new standup offers both platforms and a Teams channel picker" do
    get new_manager_standup_path(platform: "teams")

    assert_response :success
    assert_select "#platform-picker a", text: /Slack/
    assert_select "#platform-picker a.btn-primary", text: /Microsoft Teams/
    assert_select "input[type=hidden][name='standup[platform]'][value=teams]"
    assert_select "select[name='standup[platform_channel]'] option[value='#{TEAMS_CHANNEL}']", text: "Engineering › Standup"
    assert_includes response.body, "Asked one at a time in a Microsoft Teams DM"
  end

  test "creates a Teams standup with Teams participants" do
    assert_difference "Standup.count", 1 do
      post manager_standups_path, params: {
        standup: {
          name: "Teams Daily",
          platform: "teams",
          platform_channel: TEAMS_CHANNEL,
          platform_channel_name: "Engineering › Standup",
          question_rows: [ "What changed?" ],
          schedule_type: "weekly",
          schedule_days: [ "1" ],
          send_time: "09:15",
          respect_timezone: "true",
          active: "true",
          participants: { "0" => { platform_user_id: TEAMS_USER_ID.upcase, display_name: "Tess Teams", active: "1" } }
        }
      }
    end

    standup = Standup.order(:id).last
    assert_equal "teams", standup.platform
    assert_equal "Engineering › Standup", standup.channel_reference
    assert_equal [ TEAMS_USER_ID ], standup.standup_participants.pluck(:platform_user_id)
  end

  test "editing can't move a standup to another platform" do
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)

    patch manager_standup_path(standup), params: { standup: { name: "Renamed", platform: "slack" } }

    assert_equal "teams", standup.reload.platform
    assert_equal "Renamed", standup.name
  end

  test "editing keeps the current channel selectable when discovery doesn't list it" do
    standup = create_teams_standup!
    standup.update!(platform_channel: "#{TEAMS_TEAM_ID}|19:private@thread.tacv2", platform_channel_name: "Engineering › Private")
    standup.standup_ownerships.create!(user: @manager)

    get edit_manager_standup_path(standup)

    assert_response :success
    assert_select "select[name='standup[platform_channel]'] option[selected][value='#{TEAMS_TEAM_ID}|19:private@thread.tacv2']", text: "Engineering › Private"
  end

  test "the standup's chat tab is labeled for Teams and finds Teams channels" do
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    TeamsIntegrationService.any_instance.stubs(:connection_status).returns(ChatIntegrationService::Result.new(status: "ok", message: "ok", metadata: {}))

    get manager_standup_chat_setup_path(standup), params: { discover: "channels" }

    assert_response :success
    assert_select "nav.tabs a.is-active", text: /Microsoft Teams/
    assert_select "#teams-channel-results", text: /Engineering › Standup/
  end

  test "the integrations page has a tab per platform" do
    TeamsIntegrationService.any_instance.stubs(:connection_status).returns(ChatIntegrationService::Result.new(status: "ok", message: "ok", metadata: {}))

    get manager_integrations_path(platform: "teams")

    assert_response :success
    assert_select "nav[aria-label='Chat platforms'] a", count: 2
    assert_select "#teams-status h2", text: "Microsoft Teams app status"
  end

  test "old Slack URLs redirect" do
    get "/manager/slack_integration"
    assert_redirected_to "/manager/integrations"

    get "/manager/standups/#{standups(:daily).id}/slack_setup"
    assert_redirected_to "/manager/standups/#{standups(:daily).id}/chat_setup"
  end
end

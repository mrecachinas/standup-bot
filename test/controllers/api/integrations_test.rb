require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::IntegrationsTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  ADMIN_TOKEN = "admin-access-token".freeze

  setup do
    @manager = users(:manager)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    stub_slack_status
  end

  test "requires authentication" do
    get api_integrations_path, as: :json

    assert_response :unauthorized
  end

  test "any manager sees Slack status without secrets and only standups they manage" do
    sign_in(@manager, "manager-access-token")

    get api_integrations_path(platform: "slack"), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "slack", body["platform"]
    assert_equal ChatPlatform.keys.map(&:to_s), body["platforms"].map { |platform| platform["key"] }
    slack_tab = body["platforms"].find { |platform| platform["key"] == "slack" }
    assert_equal "Connected", slack_tab["status_label"]
    assert_equal "Slack app status", body.dig("integration_status", "title")
    assert_equal "Slack API authentication succeeded.", body.dig("integration_status", "connection", "message")
    assert_equal [ @owned_standup.id ], body["standups"].map { |standup| standup["id"] }
    assert_equal @owned_standup.channel_reference, body["standups"].first["channel_reference"]
    assert_equal PlatformSerializer.copy_for(:slack, :channel_search_placeholder), body.dig("copy", "channel_search_placeholder")
    assert_not_includes response.body, "xoxb-secret"
    assert_not_includes response.body, "signing-secret"
  end

  test "channel discovery surfaces Slack records" do
    SlackIntegrationService.any_instance.expects(:discover_channels)
      .with(query: "gen", include_private: false)
      .returns(SlackIntegrationService::Result.new(status: "ok", records: [ { "id" => "C123", "label" => "#general" } ], message: "Found 1 Slack channel(s)."))
    sign_in(@manager, "manager-access-token")

    get api_integrations_path(platform: "slack", discover: "channels", channel_query: "gen"), as: :json

    assert_response :success
    result = response.parsed_body["channel_result"]
    assert_equal "Found 1 Slack channel(s).", result["message"]
    assert_equal [ [ "C123", "#general" ] ], result["records"].map { |record| [ record["id"], record["label"] ] }
  end

  test "admins see private channels and every standup" do
    SlackIntegrationService.any_instance.expects(:discover_channels).with(query: nil, include_private: true)
      .returns(SlackIntegrationService::Result.new(status: "ok", records: []))
    sign_in(users(:admin), "admin-access-token")

    get api_integrations_path(platform: "slack", discover: "channels"), as: :json

    assert_response :success
    assert_equal Standup.count, response.parsed_body["standups"].size
  end

  test "an admin's token can read integration status" do
    get api_integrations_path(platform: "slack"), headers: token_headers, as: :json

    assert_response :success
    assert_equal Standup.count, response.parsed_body["standups"].size
  end

  test "there's a tab per platform and Teams has its own status" do
    enable_teams!
    TeamsIntegrationService.any_instance.stubs(:connection_status).returns(ChatIntegrationService::Result.new(status: "ok", message: "ok", metadata: {}))
    TeamsIntegrationService.any_instance.expects(:discover_users).with(query: "tess").returns(
      ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => TEAMS_USER_ID, "label" => "Tess Teams", "email" => "tess@contoso.com" } ])
    )
    sign_in(@manager, "manager-access-token")

    get api_integrations_path(platform: "teams", user_query: "tess"), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "teams", body["platform"]
    assert_equal 2, body["platforms"].size
    teams_tab = body["platforms"].find { |platform| platform["key"] == "teams" }
    assert_equal "Microsoft Teams", teams_tab["label"]
    assert teams_tab["configured"]
    assert_equal "Microsoft Teams app status", body.dig("integration_status", "title")
    assert_equal PlatformSerializer.copy_for(:teams, :user_search_placeholder), body.dig("copy", "user_search_placeholder")
    record = body.dig("user_result", "records").sole
    assert_equal "user", record["kind"]
    assert_equal "Tess Teams", record["label"]
    assert_not_includes response.body, "teams-test-secret"
  end

  test "an unknown platform falls back to the default" do
    sign_in(@manager, "manager-access-token")

    get api_integrations_path(platform: "irc"), as: :json

    assert_response :success
    assert_includes ChatPlatform.keys.map(&:to_s), response.parsed_body["platform"]
  end

  private

  def stub_slack_status
    SlackIntegrationService.any_instance.stubs(:configuration_status).returns(slack_status)
    SlackIntegrationService.any_instance.stubs(:connection_status).returns(
      SlackIntegrationService::Result.new(status: "ok", message: "Slack API authentication succeeded.", metadata: { "team" => "Example" })
    )
    SlackIntegrationService.any_instance.stubs(:discover_channels).returns(SlackIntegrationService::Result.new(status: "ok", records: []))
    SlackIntegrationService.any_instance.stubs(:discover_users).returns(SlackIntegrationService::Result.new(status: "ok", records: []))
  end

  def slack_status
    {
      configured: true,
      installation: { message: "Slack app bot token is configured." },
      credentials: {
        bot_token: { label: "Bot token", configured: true, required: true, message: "Bot token is configured." },
        signing_secret: { label: "Signing secret", configured: true, required: true, message: "Signing secret is configured." },
        client_id: { label: "Client ID", configured: false, required: false, message: "Client ID is optional." },
        client_secret: { label: "Client secret", configured: false, required: false, message: "Client secret is optional." }
      }
    }
  end

  def token_headers
    { "Authorization" => "Bearer #{ADMIN_TOKEN}" }
  end

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end
end

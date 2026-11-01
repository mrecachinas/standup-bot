require "test_helper"
require_relative "../support/teams_test_helper"

class TeamsIntegrationServiceTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    enable_teams!
    @client = ChatPlatform::TeamsAdapter.new(connector: mock("connector"), graph: mock("graph"))
    @service = TeamsIntegrationService.new(client: @client, config: Rails.application.config.teams)
  end

  test "reports Teams credentials without exposing secrets" do
    status = @service.configuration_status

    assert status[:configured]
    assert_equal "Microsoft Teams", status[:label]
    assert_equal true, status[:credentials][:app_password][:configured]
    assert_not_includes status.to_json, "teams-test-secret"
  end

  test "explains which settings are missing" do
    service = TeamsIntegrationService.new(client: @client, config: { app_id: TEAMS_APP_ID })

    result = service.discover_channels
    assert_not result.success?
    assert_equal "missing_app_password", result.error_code
    assert_equal "Set TEAMS_APP_PASSWORD and restart the app.", result.action
  end

  test "accepts object IDs without calling Graph" do
    @client.expects(:search_users).never

    result = @service.resolve_user(TEAMS_USER_ID.upcase)
    assert_equal TEAMS_USER_ID, result.records.first["id"]
  end

  test "resolves people by email" do
    @client.expects(:search_users).with(query: "tess@contoso.com", limit: 200).returns([
      { "id" => TEAMS_USER_ID, "label" => "Tess Teams", "email" => "tess@contoso.com" },
      { "id" => "other", "label" => "Tessa", "email" => "tessa@contoso.com" }
    ])

    assert_equal TEAMS_USER_ID, @service.resolve_user("tess@contoso.com").records.first["id"]
  end

  test "maps a missing app install to an actionable error" do
    standup = create_teams_standup!
    @client.expects(:send_message).raises(ChatPlatform::TeamsAdapter::NotInstalled.new("not installed", status: 403))

    result = @service.test_message(standup)

    assert_equal "teams_app_not_installed", result.error_code
    assert_match "TEAMS_APP_CATALOG_ID", result.action
  end

  test "hides the client secret in error messages" do
    @client.expects(:list_channels).raises(StandardError, "boom teams-test-secret")

    result = @service.discover_channels
    assert_not_includes result.message, "teams-test-secret"
    assert_includes result.message, "[FILTERED]"
  end
end

require "test_helper"
require_relative "../../support/teams_test_helper"

# GET /api/people: the people picker's search against a chat platform.
class Api::PeopleTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = "test-admin-token"
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "requires authentication" do
    get api_people_path(q: "ada"), as: :json

    assert_response :unauthorized
  end

  test "searches Slack people" do
    SlackIntegrationService.any_instance.expects(:discover_users).with(query: "ada", limit: 20).returns(
      ChatIntegrationService::Result.new(
        status: "ok",
        message: "Found 2 Slack user(s).",
        records: [
          { "id" => "UADA1", "name" => "ada", "display_name" => "Ada", "label" => "Ada", "tz" => "Europe/London", "avatar_url" => "https://avatars.example.com/ada.png" },
          { "id" => "UADA2", "name" => "ada.l", "label" => "Ada L", "avatar_url" => "javascript:alert(1)" }
        ]
      )
    )
    sign_in(users(:manager), "manager-access-token")

    get api_people_path(platform: "slack", q: " ada "), as: :json

    assert_response :success
    assert_equal(
      {
        "platform" => "slack",
        "people" => [
          { "platform_user_id" => "UADA1", "display_name" => "Ada", "avatar_url" => "https://avatars.example.com/ada.png", "timezone" => "Europe/London" },
          { "platform_user_id" => "UADA2", "display_name" => "Ada L", "avatar_url" => nil, "timezone" => nil }
        ],
        "success" => true,
        "message" => "Found 2 Slack user(s)."
      },
      response.parsed_body
    )
  end

  test "searches Teams people for Teams standups" do
    enable_teams!
    TeamsIntegrationService.any_instance.expects(:discover_users).with(query: "tess", limit: 5).returns(
      ChatIntegrationService::Result.new(
        status: "ok",
        message: "Found 1 Microsoft Teams user(s).",
        records: [ { "id" => TEAMS_USER_ID, "name" => "tess@contoso.com", "display_name" => "Tess Teams", "label" => "Tess Teams" } ]
      )
    )
    sign_in(users(:manager), "manager-access-token")

    get api_people_path(platform: "teams", q: "tess", limit: 5), as: :json

    assert_response :success
    assert_equal [ { "platform_user_id" => TEAMS_USER_ID, "display_name" => "Tess Teams", "avatar_url" => nil, "timezone" => nil } ], response.parsed_body["people"]
  end

  test "passes along a failed search" do
    SlackIntegrationService.any_instance.stubs(:discover_users).returns(
      ChatIntegrationService::Result.new(status: "error", message: "Slack isn't set up yet.", error_code: "missing_config")
    )
    sign_in(users(:manager), "manager-access-token")

    get api_people_path(q: "ada"), as: :json

    assert_response :success
    assert_equal({ "platform" => "slack", "people" => [], "success" => false, "message" => "Slack isn't set up yet." }, response.parsed_body)
  end

  test "rejects unknown platforms" do
    sign_in(users(:manager), "manager-access-token")

    get api_people_path(platform: "irc", q: "ada"), as: :json

    assert_response :unprocessable_entity
  end

  test "clamps the limit and lets the token search" do
    SlackIntegrationService.any_instance.expects(:discover_users).with(query: nil, limit: ChatIntegrationService::MAX_LIMIT).returns(
      ChatIntegrationService::Result.new(status: "ok", message: "Found 0 Slack user(s).", records: [])
    )

    get api_people_path(platform: "slack", limit: 10_000), headers: { "Authorization" => "Bearer test-admin-token" }, as: :json

    assert_response :success
    assert_empty response.parsed_body["people"]
  end

  private

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end
end

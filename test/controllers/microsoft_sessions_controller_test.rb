require "test_helper"
require_relative "../support/teams_test_helper"

class MicrosoftSessionsControllerTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    enable_teams!
  end

  def start_sign_in
    get microsoft_sign_in_path
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  test "starts the Entra ID flow with state and nonce" do
    query = start_sign_in

    assert_response :see_other
    assert_equal "login.microsoftonline.com", URI.parse(response.location).host
    assert_equal microsoft_sign_in_callback_url, query["redirect_uri"]
    assert query["state"].present?
    assert query["nonce"].present?
  end

  test "falls back to token sign-in when it isn't configured" do
    Rails.application.config.stubs(:teams).returns({})

    get microsoft_sign_in_path

    assert_redirected_to new_session_path
  end

  test "rejects a callback with the wrong state" do
    start_sign_in
    MicrosoftSignIn.any_instance.expects(:identity_for).never

    get microsoft_sign_in_callback_path, params: { code: "code", state: "forged" }

    assert_redirected_to new_session_path
  end

  test "signs in a Teams member and lands them on their standups" do
    standup = create_teams_standup!
    query = start_sign_in
    identity = User::Identity.new(user_id: TEAMS_USER_ID, name: "Tess Teams", email: nil, email_verified: false)
    MicrosoftSignIn.any_instance.expects(:identity_for).with(code: "code", redirect_uri: microsoft_sign_in_callback_url, nonce: query["nonce"]).returns(identity)

    assert_difference "User.count", 1 do
      get microsoft_sign_in_callback_path, params: { code: "code", state: query["state"] }
    end

    assert_redirected_to me_root_path
    user = User.find_by_identity(:teams, TEAMS_USER_ID)
    assert_equal "#{TEAMS_USER_ID}@teams-users.invalid", user.email

    get api_me_standups_path, as: :json
    assert_response :success
    assert_includes response.parsed_body["standups"].map { |entry| entry.dig("standup", "name") }, standup.name
    assert_equal "teams", response.parsed_body.dig("member", "platform")
  end

  test "offers Microsoft sign-in in the session bootstrap" do
    get api_session_path, as: :json

    teams = response.parsed_body["platforms"].find { |platform| platform["key"] == "teams" }
    assert teams["sign_in_enabled"]
  end
end

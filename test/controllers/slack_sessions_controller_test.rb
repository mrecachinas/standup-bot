require "test_helper"

class SlackSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret", team_id: "T123" })
  end

  test "starts the Slack OpenID flow with a state parameter" do
    get slack_sign_in_path

    assert_response :see_other
    location = URI.parse(response.location)
    query = Rack::Utils.parse_query(location.query)
    assert_equal "slack.com", location.host
    assert_equal "/openid/connect/authorize", location.path
    assert_equal "openid email profile", query["scope"]
    assert_equal "T123", query["team"]
    assert_equal slack_sign_in_callback_url, query["redirect_uri"]
    assert query["state"].present?
  end

  test "falls back to token sign-in when Slack sign-in isn't configured" do
    Rails.application.config.stubs(:slack).returns({})

    get slack_sign_in_path

    assert_redirected_to new_session_path
  end

  test "rejects a callback with the wrong state" do
    get slack_sign_in_path
    SlackSignIn.any_instance.expects(:identity_for).never

    get slack_sign_in_callback_path, params: { code: "abc", state: "not-the-state" }

    assert_redirected_to new_session_path
    assert_flash_from_session "Your sign-in link expired"
  end

  test "signs a participant into the member area" do
    sign_in_with_slack(platform_user_id: "U123456", email: "john@example.com")

    assert_redirected_to me_root_path
    get api_me_standups_path, as: :json
    assert_response :success
    assert_includes response.parsed_body["standups"].map { |entry| entry.dig("standup", "name") }, standups(:daily).name
  end

  test "links an existing account by verified email and lands owners in the console" do
    sign_in_with_slack(platform_user_id: "U999999", email: users(:manager).email)

    assert_redirected_to manager_standups_path
    assert_equal "U999999", users(:manager).reload.platform_user_id_for(:slack)
    get api_standups_path, as: :json
    assert_response :success
  end

  test "does not link accounts when Slack hasn't verified the email" do
    assert_difference "User.count", 1 do
      sign_in_with_slack(platform_user_id: "U123456", email: users(:admin).email, email_verified: false)
    end

    assert_redirected_to me_root_path
    assert_nil users(:admin).reload.platform_user_id_for(:slack)
    get api_admin_dashboard_path, as: :json
    assert_response :forbidden
  end

  test "anyone in the workspace can sign in and start a standup" do
    assert_difference "User.count", 1 do
      sign_in_with_slack(platform_user_id: "UVTEAM1", email: "lead@example.com")
    end

    user = User.find_by_identity!(:slack, "UVTEAM1")
    assert_equal "manager", user.role
    assert_redirected_to manager_standups_path
    get api_overview_path, as: :json
    assert_response :success
    assert response.parsed_body["empty"]
  end

  test "returning users are matched by Slack user ID" do
    users(:other_manager).link_identity!(:slack, "URETURN")

    assert_no_difference "User.count" do
      sign_in_with_slack(platform_user_id: "URETURN", email: "changed@example.com")
    end
    assert_redirected_to manager_standups_path
  end

  test "turned-off accounts can't sign in with Slack" do
    users(:inactive_manager).link_identity!(:slack, "UOFF")

    sign_in_with_slack(platform_user_id: "UOFF", email: users(:inactive_manager).email)

    assert_redirected_to new_session_path
    assert_flash_from_session "turned off"
  end

  test "refuses to relink an email that belongs to another Slack account" do
    users(:manager).link_identity!(:slack, "UORIGINAL")

    sign_in_with_slack(platform_user_id: "UIMPOSTER", email: users(:manager).email)

    assert_redirected_to new_session_path
    assert_equal "UORIGINAL", users(:manager).reload.platform_user_id_for(:slack)
  end

  test "signing in saves the Slack photo on the account and the person's standups" do
    url = "https://avatars.slack-edge.com/john.png"

    sign_in_with_slack(platform_user_id: "U123456", email: "john@example.com", avatar_url: url)

    assert_equal url, User.find_by_identity!(:slack, "U123456").avatar_url
    assert_equal url, standup_participants(:one).reload.avatar_url
  end

  private

  # Sign-in errors reach the console as a flash in the session bootstrap.
  def assert_flash_from_session(text)
    get api_session_path, as: :json
    messages = response.parsed_body["flash"].map { |flash| flash["message"] }
    assert messages.any? { |message| message.include?(text) }, "expected a flash including #{text.inspect}, got #{messages.inspect}"
  end

  def sign_in_with_slack(platform_user_id:, email:, email_verified: true, avatar_url: nil)
    get slack_sign_in_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    identity = User::Identity.new(user_id: platform_user_id, team_id: "T123", email: email, email_verified: email_verified, name: "Slack Person", avatar_url: avatar_url)
    SlackSignIn.any_instance.stubs(:identity_for).returns(identity)

    get slack_sign_in_callback_path, params: { code: "oauth-code", state: state }
  end
end

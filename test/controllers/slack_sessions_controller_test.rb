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
    follow_redirect!
    assert_includes response.body, "Your sign-in link expired"
  end

  test "signs a participant into the member area" do
    sign_in_with_slack(slack_id: "U123456", email: "john@example.com")

    assert_redirected_to me_root_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, standups(:daily).name
  end

  test "links an existing account by verified email and lands owners in the console" do
    sign_in_with_slack(slack_id: "U999999", email: users(:manager).email)

    assert_redirected_to manager_standups_path
    assert_equal "U999999", users(:manager).reload.slack_user_id
    follow_redirect!
    assert_response :success
  end

  test "does not link accounts when Slack hasn't verified the email" do
    assert_difference "User.count", 1 do
      sign_in_with_slack(slack_id: "U123456", email: users(:admin).email, email_verified: false)
    end

    assert_redirected_to me_root_path
    assert_nil users(:admin).reload.slack_user_id
    get admin_root_path
    assert_response :forbidden
  end

  test "anyone in the workspace can sign in and start a standup" do
    assert_difference "User.count", 1 do
      sign_in_with_slack(slack_id: "UVTEAM1", email: "lead@example.com")
    end

    user = User.find_by!(slack_user_id: "UVTEAM1")
    assert_equal "manager", user.role
    assert_redirected_to manager_standups_path
    follow_redirect!
    assert_includes response.body, "Create your first standup"
  end

  test "returning users are matched by Slack user ID" do
    users(:other_manager).update!(slack_user_id: "URETURN")

    assert_no_difference "User.count" do
      sign_in_with_slack(slack_id: "URETURN", email: "changed@example.com")
    end
    assert_redirected_to manager_standups_path
  end

  test "turned-off accounts can't sign in with Slack" do
    users(:inactive_manager).update!(slack_user_id: "UOFF")

    sign_in_with_slack(slack_id: "UOFF", email: users(:inactive_manager).email)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_includes response.body, "turned off"
  end

  test "refuses to relink an email that belongs to another Slack account" do
    users(:manager).update!(slack_user_id: "UORIGINAL")

    sign_in_with_slack(slack_id: "UIMPOSTER", email: users(:manager).email)

    assert_redirected_to new_session_path
    assert_equal "UORIGINAL", users(:manager).reload.slack_user_id
  end

  private

  def sign_in_with_slack(slack_id:, email:, email_verified: true)
    get slack_sign_in_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    identity = SlackSignIn::Identity.new(slack_id: slack_id, team_id: "T123", email: email, email_verified: email_verified, name: "Slack Person")
    SlackSignIn.any_instance.stubs(:identity_for).returns(identity)

    get slack_sign_in_callback_path, params: { code: "oauth-code", state: state }
  end
end

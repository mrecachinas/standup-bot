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

  test "signs a manager with a matching verified email into the console" do
    sign_in_with_slack(slack_id: "U999999", email: users(:manager).email)

    assert_redirected_to manager_standups_path
    follow_redirect!
    assert_response :success
  end

  test "does not link accounts when Slack hasn't verified the email" do
    sign_in_with_slack(slack_id: "U123456", email: users(:admin).email, email_verified: false)

    assert_redirected_to me_root_path
    get admin_root_path
    assert_redirected_to me_root_path
  end

  test "refuses people who aren't in a standup and have no account" do
    sign_in_with_slack(slack_id: "UNOBODY", email: "nobody@example.com")

    assert_redirected_to new_session_path
    follow_redirect!
    assert_includes response.body, "not part of any standups"
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

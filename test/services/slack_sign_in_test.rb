require "test_helper"

class SlackSignInTest < ActiveSupport::TestCase
  setup do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret", team_id: "T123" })
    SlackClient.any_instance.stubs(:get_user_info).returns("name" => "john", "is_restricted" => false, "is_ultra_restricted" => false, "deleted" => false, "is_bot" => false)
  end

  test "exchanges the code and reads the Slack identity" do
    Slack::Web::Client.any_instance.expects(:openid_connect_token)
      .with(client_id: "123.456", client_secret: "client-secret", code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
      .returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "sub" => "U123456",
      "https://slack.com/user_id" => "U123456",
      "https://slack.com/team_id" => "T123",
      "email" => "john@example.com",
      "email_verified" => true,
      "name" => "John Doe",
      "https://slack.com/user_image_72" => "https://avatars.slack-edge.com/john_72.png"
    )

    identity = SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")

    assert_equal "U123456", identity.slack_id
    assert_equal "john@example.com", identity.email
    assert identity.email_verified
    assert_equal "John Doe", identity.name
    assert_equal "https://avatars.slack-edge.com/john_72.png", identity.avatar_url
  end

  test "rejects identities from another workspace" do
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "https://slack.com/user_id" => "U123456",
      "https://slack.com/team_id" => "TOTHER"
    )

    error = assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
    assert_match "workspace", error.message
  end

  test "wraps Slack API errors" do
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).raises(Slack::Web::Api::Errors::SlackError.new("invalid_code"))

    assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
  end
  test "falls back to the bot token's workspace when SLACK_TEAM_ID isn't set" do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret" })
    Rails.cache.delete("slack_sign_in/bot_team_id")
    SlackClient.any_instance.stubs(:auth_test).returns("ok" => true, "team_id" => "TBOT")
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "https://slack.com/user_id" => "U123456",
      "https://slack.com/team_id" => "TELSEWHERE",
      "email" => "admin@example.com",
      "email_verified" => true
    )

    assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
  end

  test "refuses sign-in when no workspace can be determined" do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret" })
    Rails.cache.delete("slack_sign_in/bot_team_id")
    SlackClient.any_instance.stubs(:auth_test).raises(StandardError, "invalid_auth")
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "https://slack.com/user_id" => "U123456",
      "https://slack.com/team_id" => "T123"
    )

    error = assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
    assert_match "SLACK_TEAM_ID", error.message
  end

  test "rejects Slack guests" do
    SlackClient.any_instance.stubs(:get_user_info).returns("name" => "guest", "is_restricted" => true)
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "https://slack.com/user_id" => "UGUEST",
      "https://slack.com/team_id" => "T123"
    )

    error = assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
    assert_match "Guest", error.message
  end

  test "refuses sign-in when Slack can't confirm the account" do
    SlackClient.any_instance.stubs(:get_user_info).returns(nil)
    Slack::Web::Client.any_instance.stubs(:openid_connect_token).returns("access_token" => "xoxp-user")
    Slack::Web::Client.any_instance.stubs(:openid_connect_userInfo).returns(
      "https://slack.com/user_id" => "U123456",
      "https://slack.com/team_id" => "T123"
    )

    assert_raises(SlackSignIn::Error) do
      SlackSignIn.new.identity_for(code: "abc", redirect_uri: "https://app.example.com/auth/slack/callback")
    end
  end
end

require "test_helper"

class SlackConfigTest < ActiveSupport::TestCase
  test "defaults to http mode and needs the signing secret" do
    config = { bot_token: "xoxb-token", signing_secret: "secret" }

    assert_equal "http", SlackConfig.connection_mode(config)
    assert_not SlackConfig.socket_mode?(config)
    assert_equal :signing_secret, SlackConfig.inbound_credential_key(config)
    assert SlackConfig.configured?(config)
    assert_not SlackConfig.configured?(config.merge(signing_secret: nil))
  end

  test "socket mode needs the app-level token instead of the signing secret" do
    config = { bot_token: "xoxb-token", connection_mode: " Socket ", app_token: "xapp-token" }

    assert SlackConfig.socket_mode?(config)
    assert_equal "Socket Mode", SlackConfig.connection_mode_label(config)
    assert SlackConfig.configured?(config)
    assert_not SlackConfig.configured?(config.merge(app_token: nil))
  end

  test "validate! rejects unknown modes but allows blank" do
    assert_nothing_raised { SlackConfig.validate!({ connection_mode: "" }) }
    assert_nothing_raised { SlackConfig.validate!({ connection_mode: "http" }) }

    error = assert_raises(ArgumentError) { SlackConfig.validate!({ connection_mode: "sockets" }) }
    assert_match "SLACK_CONNECTION_MODE must be one of http, socket", error.message
  end
end

require "test_helper"

class SlackIntegrationServiceTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
    @client = mock("SlackClient")
    @config = {
      bot_token: "xoxb-secret-token",
      signing_secret: "super-secret-signing-value",
      client_id: "client-id",
      client_secret: "client-secret-value"
    }
    HealthCheckService.stubs(:slack_status).returns({ status: "ok", configured: true })
  end

  test "configuration status reports presence without exposing secret values" do
    status = service.configuration_status
    serialized = status.to_json

    assert_equal "ok", status[:status]
    assert status[:credentials][:bot_token][:configured]
    assert status[:credentials][:signing_secret][:configured]
    assert_not_includes serialized, @config[:bot_token]
    assert_not_includes serialized, @config[:signing_secret]
    assert_not_includes serialized, @config[:client_secret]
  end

  test "connection status validates Slack auth through client" do
    @client.expects(:auth_test).returns({ "team" => "Example", "team_id" => "T123", "user_id" => "U999" })

    result = service.connection_status

    assert result.success?
    assert_equal "Example", result.metadata["team"]
    assert_equal "U999", result.metadata["user_id"]
  end

  test "discovery returns channels from Slack client" do
    channels = [ { "id" => "C123", "name" => "general", "label" => "#general" } ]
    @client.expects(:list_channels).with(query: "gen", limit: 50).returns(channels)

    result = service.discover_channels(query: "gen", limit: 50)

    assert result.success?
    assert_equal channels, result.records
  end

  test "missing bot token produces actionable configuration error" do
    @client.expects(:list_users).never

    result = SlackIntegrationService.new(client: @client, config: {}).discover_users(query: "alice")

    assert_not result.success?
    assert_equal "missing_bot_token", result.error_code
    assert_includes result.action, "SLACK_BOT_TOKEN"
  end

  test "Slack API errors are mapped to actionable messages without leaking secrets" do
    @client.expects(:list_channels).raises(StandardError.new("invalid_auth #{@config[:bot_token]}"))

    result = service.discover_channels

    assert_not result.success?
    assert_includes result.message, "Slack API could not discover Slack channels"
    assert_not_includes result.message, @config[:bot_token]
    assert_includes result.message, "[FILTERED]"
  end

  test "test message sends to configured standup channel" do
    @client.expects(:send_message)
      .with(@standup.slack_channel, includes(@standup.name))
      .returns({ "channel" => "C123", "ts" => "123.456" })

    result = service.test_message(@standup)

    assert result.success?
    assert_equal({ "channel" => "C123", "ts" => "123.456" }, result.metadata)
  end

  private

  def service
    SlackIntegrationService.new(client: @client, config: @config)
  end
end

require "test_helper"

class SlackIntegrationServiceTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
    @client = ChatPlatform::SlackAdapter.new
    @config = {
      bot_token: "xoxb-secret-token",
      signing_secret: "super-secret-signing-value",
      client_id: "client-id",
      client_secret: "client-secret-value"
    }
    HealthCheckService.stubs(:platform_status).returns({ status: "ok", configured: true })
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

  test "socket mode asks for the app-level token instead of the signing secret" do
    @config = @config.except(:signing_secret).merge(connection_mode: "socket", app_token: "xapp-1-secret-app-token")

    status = service.configuration_status

    assert_equal "ok", status[:status]
    assert_equal %i[bot_token app_token client_id client_secret], status[:credentials].keys
    assert status[:credentials][:app_token][:required]
    assert_match "Socket Mode", status.dig(:installation, :message)
    assert_not_includes status.to_json, @config[:app_token]
  end

  test "socket mode without an app-level token isn't ready" do
    @config = @config.merge(connection_mode: "socket")

    status = service.configuration_status

    assert_equal "warn", status[:status]
    assert_not status[:credentials][:app_token][:configured]
  end

  test "connection status validates Slack auth through client" do
    @client.expects(:connection_status).returns({ "team" => "Example", "team_id" => "T123", "user_id" => "U999" })

    result = service.connection_status

    assert result.success?
    assert_equal "Example", result.metadata["team"]
    assert_equal "U999", result.metadata["user_id"]
  end

  test "discovery returns channels from Slack client" do
    channels = [ { "id" => "C123", "name" => "general", "label" => "#general" } ]
    @client.expects(:list_channels).with(query: "gen", limit: 50, include_private: true).returns(channels)

    result = service.discover_channels(query: "gen", limit: 50)

    assert result.success?
    assert_equal channels, result.records
  end

  test "resolves Slack username to exact user record" do
    users = [
      { "id" => "U123", "name" => "alice", "label" => "Alice Doe", "real_name" => "Alice Doe", "tz" => "America/New_York" },
      { "id" => "U999", "name" => "malice", "label" => "Malice" }
    ]
    @client.expects(:search_users).with(query: "alice", limit: 200).returns(users)

    result = service.resolve_user("@alice")

    assert result.success?
    assert_equal "U123", result.records.first["id"]
    assert_equal "America/New_York", result.records.first["tz"]
  end

  test "resolves Slack IDs without requiring Slack API" do
    @client.expects(:search_users).never

    result = SlackIntegrationService.new(client: @client, config: {}).resolve_user("u123")

    assert result.success?
    assert_equal "U123", result.records.first["id"]
  end

  test "ambiguous Slack username resolution is actionable" do
    users = [
      { "id" => "U123", "name" => "alex", "label" => "Alex" },
      { "id" => "U456", "display_name" => "alex", "label" => "Alex Backup" }
    ]
    @client.expects(:search_users).with(query: "alex", limit: 200).returns(users)

    result = service.resolve_user("alex")

    assert_not result.success?
    assert_equal "ambiguous_user", result.error_code
    assert_includes result.action, "more specific"
  end

  test "missing bot token produces actionable configuration error" do
    @client.expects(:search_users).never

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
      .with(@standup.platform_channel, includes(@standup.name))
      .returns(ChatPlatform::MessageRef.new(channel: "C123", id: "123.456"))

    result = service.test_message(@standup)

    assert result.success?
    assert_equal({ "channel" => "C123", "ts" => "123.456" }, result.metadata)
  end

  test "discovery says when private channels were left out" do
    channels = ChatPlatform::ChannelList.new([ { "id" => "C123", "name" => "general", "label" => "#general" } ], notice: "Private channels aren't listed.")
    @client.expects(:list_channels).with(query: nil, limit: 100, include_private: true).returns(channels)

    result = service.discover_channels

    assert result.success?
    assert_equal [ "C123" ], result.records.map { |record| record["id"] }
    assert_equal "Found 1 Slack channel(s).", result.message
    assert_equal "Private channels aren't listed.", result.action
  end

  test "private channels only show up in discovery for admins" do
    records = [ { "id" => "C1", "label" => "#general", "is_private" => false }, { "id" => "G1", "label" => "#secret-project", "is_private" => true } ]
    client = ChatPlatform::SlackAdapter.new.tap { |adapter| adapter.stubs(:list_channels).returns(records) }
    service = SlackIntegrationService.new(client: client, config: { bot_token: "xoxb-test" })

    assert_equal [ "C1" ], service.discover_channels(query: nil, include_private: false).records.map { |record| record["id"] }
    assert_equal 2, service.discover_channels(query: nil).records.size
  end

  private

  def service
    SlackIntegrationService.new(client: @client, config: @config)
  end
end

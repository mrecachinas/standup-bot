require "test_helper"

class SlackClientTest < ActiveSupport::TestCase
  setup do
    SlackClient.reset!
    @slack_client = SlackClient.new
    # Mock the Slack::Web::Client
    @mock_api_client = mock("Slack::Web::Client")
    @slack_client.instance_variable_set(:@client, @mock_api_client)
  end

  test "reset clears singleton instance for token rotation" do
    first_instance = SlackClient.instance

    SlackClient.reset!

    second_instance = SlackClient.instance
    assert_not_equal first_instance.object_id, second_instance.object_id
  end

  test "send_message with simple text" do
    channel = "C12345"
    message = "Hello, world!"
    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }
    slack_response = Slack::Messages::Message.new(expected_response)

    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, text: message, as_user: true)
      .returns(slack_response)

    response = @slack_client.send_message(channel, message)
    assert_equal expected_response, response
  end

  test "send_message with blocks" do
    channel = "C12345"
    message = "Hello, world!"
    blocks = [ { type: "section", text: { type: "mrkdwn", text: message } } ]
    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }
    slack_response = Slack::Messages::Message.new(expected_response)

    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, blocks: blocks, text: message, as_user: true)
      .returns(slack_response)

    response = @slack_client.send_message(channel, message, blocks)
    assert_equal expected_response, response
  end

  test "get_user_info successful" do
    slack_id = "U12345"

    @mock_api_client.expects(:users_info)
      .with(user: slack_id)
      .returns(slack_user_info_response("John Doe", "America/New_York", tz_offset: -18000))

    result = @slack_client.get_user_info(slack_id)
    assert_equal({ "name" => "John Doe", "tz" => "America/New_York", "tz_offset" => -18000, "profile" => {} }, result.slice("name", "tz", "tz_offset", "profile"))
  end

  test "get_user_info handles user not found" do
    slack_id = "U12345"

    @mock_api_client.expects(:users_info)
      .with(user: slack_id)
      .raises(Slack::Web::Api::Errors::UserNotFound.new("user_not_found"))

    result = @slack_client.get_user_info(slack_id)
    assert_nil result
  end

  test "channel_members follows pagination cursors" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.members", { channel: "C12345", limit: 200, cursor: nil })
      .returns(slack_message("members" => [ "U111" ], "response_metadata" => { "next_cursor" => "page-2" }))
    api.expects(:post)
      .with("conversations.members", { channel: "C12345", limit: 200, cursor: "page-2" })
      .returns(slack_message("members" => [ "U222" ], "response_metadata" => { "next_cursor" => "" }))

    assert_equal [ "U111", "U222" ], slack_client.channel_members("C12345")
  end

  test "channel_members resolves channel names before listing members" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel,private_channel", cursor: nil })
      .returns(slack_message("channels" => [ { "id" => "CRANDOM", "name" => "random" } ], "response_metadata" => { "next_cursor" => "page-2" }))
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel,private_channel", cursor: "page-2" })
      .returns(slack_message("channels" => [ { "id" => "CGENERAL", "name" => "general" } ], "response_metadata" => { "next_cursor" => "page-3" }))
    api.expects(:post)
      .with("conversations.members", { channel: "CGENERAL", limit: 200, cursor: nil })
      .returns(slack_message("members" => [ "U111" ], "response_metadata" => { "next_cursor" => "" }))

    assert_equal [ "U111" ], slack_client.channel_members("#general")
  end

  test "channel_members stops retrying rate limits after the configured attempts" do
    slack_client, api = slack_client_with_real_api
    rate_limit_response = stub(headers: { "retry-after" => "1" })
    api.expects(:post)
      .with("conversations.members", { channel: "C12345", limit: 200, cursor: nil })
      .times(SlackClient::MAX_RATE_LIMIT_RETRIES + 1)
      .raises(Slack::Web::Api::Errors::TooManyRequestsError.new(rate_limit_response))
    Slack::Web::Api::Pagination::Cursor.any_instance.expects(:sleep).with(1).times(SlackClient::MAX_RATE_LIMIT_RETRIES)

    assert_raises(Slack::Web::Api::Errors::TooManyRequestsError) { slack_client.channel_members("C12345") }
  end

  test "channel_members explains unknown channel names instead of returning nobody" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel,private_channel", cursor: nil })
      .returns(slack_message("channels" => [], "response_metadata" => { "next_cursor" => "" }))

    error = assert_raises(ChatPlatform::ChannelAccessError) { slack_client.channel_members("missing-channel") }
    assert_equal "Slack couldn't find #missing-channel. Check the channel, and invite the bot if it's private.", error.message
  end

  test "channel_members falls back to public channels without the groups:read scope" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel,private_channel", cursor: nil })
      .raises(Slack::Web::Api::Errors::MissingScope.new("missing_scope"))
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel", cursor: nil })
      .returns(slack_message("channels" => [ { "id" => "CTEST", "name" => "standup-bot-test" } ], "response_metadata" => { "next_cursor" => "" }))
    api.expects(:post)
      .with("conversations.members", { channel: "CTEST", limit: 200, cursor: nil })
      .returns(slack_message("members" => [ "U111" ], "response_metadata" => { "next_cursor" => "" }))

    assert_equal [ "U111" ], slack_client.channel_members("standup-bot-test")
  end

  test "channel_members mentions the missing scope when a name can't be found among public channels" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel,private_channel", cursor: nil })
      .raises(Slack::Web::Api::Errors::MissingScope.new("missing_scope"))
    api.expects(:post)
      .with("conversations.list", { limit: 200, exclude_archived: true, types: "public_channel", cursor: nil })
      .returns(slack_message("channels" => [], "response_metadata" => { "next_cursor" => "" }))

    error = assert_raises(ChatPlatform::ChannelAccessError) { slack_client.channel_members("#secret") }
    assert_includes error.message, "Slack couldn't find #secret."
    assert_includes error.message, "groups:read"
  end

  test "channel_members explains unknown channel IDs" do
    slack_client, api = slack_client_with_real_api
    api.expects(:post)
      .with("conversations.members", { channel: "CGONE", limit: 200, cursor: nil })
      .raises(Slack::Web::Api::Errors::ChannelNotFound.new("channel_not_found"))

    error = assert_raises(ChatPlatform::ChannelAccessError) { slack_client.channel_members("CGONE") }
    assert_includes error.message, "Slack couldn't find CGONE."
  end

  test "send_message retries rate limit errors" do
    channel = "C12345"
    message = "Hello, world!"
    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }
    slack_response = Slack::Messages::Message.new(expected_response)

    # Create a mock Faraday response with proper rate limit headers
    mock_response = mock("Faraday::Response")
    mock_response.stubs(:status).returns(429)
    mock_response.stubs(:headers).returns({ "retry-after" => "1" })
    mock_response.stubs(:body).returns('{"error": "too_many_requests"}')

    # Create a rate limit error with the proper response object
    rate_limit_error = Slack::Web::Api::Errors::TooManyRequestsError.new(mock_response)

    sequence = sequence("rate limited send")
    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, text: message, as_user: true)
      .in_sequence(sequence)
      .raises(rate_limit_error)
    @slack_client.expects(:sleep).with(1).once
    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, text: message, as_user: true)
      .in_sequence(sequence)
      .returns(slack_response)

    assert_equal expected_response, @slack_client.send_message(channel, message)
  end

  private

  def slack_message(attributes)
    Slack::Messages::Message.new(attributes)
  end

  def slack_user_info_response(name, timezone, tz_offset: 0)
    slack_message("ok" => true, "user" => { "name" => name, "tz" => timezone, "tz_offset" => tz_offset, "profile" => {} })
  end

  def slack_client_with_real_api
    slack_client = SlackClient.new
    [ slack_client, slack_client.instance_variable_get(:@client) ]
  end

  test "auth_test normalizes Slack auth response" do
    @mock_api_client.expects(:auth_test)
      .returns(slack_message("ok" => true, "team" => "Example", "team_id" => "T123", "user_id" => "U999"))

    result = @slack_client.auth_test

    assert_equal true, result["ok"]
    assert_equal "Example", result["team"]
    assert_equal "U999", result["user_id"]
  end

  test "list_channels normalizes and filters channels" do
    @mock_api_client.expects(:conversations_list)
      .with(exclude_archived: true, limit: 100, types: "public_channel,private_channel")
      .returns(slack_message(
        "channels" => [
          { "id" => "C123", "name" => "general", "is_private" => false, "is_member" => true, "num_members" => 12 },
          { "id" => "C999", "name" => "random", "is_private" => false }
        ]
      ))

    channels = @slack_client.list_channels(query: "gen")

    assert_nil channels.notice
    assert_equal 1, channels.size
    assert_equal "C123", channels.first["id"]
    assert_equal "#general", channels.first["label"]
    assert_equal true, channels.first["is_member"]
  end

  test "list_channels only asks for public channels when private ones aren't wanted" do
    @mock_api_client.expects(:conversations_list)
      .with(exclude_archived: true, limit: 100, types: "public_channel")
      .returns(slack_message("channels" => [ { "id" => "C123", "name" => "general" } ]))

    channels = @slack_client.list_channels(include_private: false)

    assert_equal [ "C123" ], channels.map { |channel| channel["id"] }
    assert_nil channels.notice
  end

  test "list_channels falls back to public channels without the groups:read scope" do
    sequence = sequence("scope fallback")
    @mock_api_client.expects(:conversations_list)
      .with(exclude_archived: true, limit: 100, types: "public_channel,private_channel")
      .in_sequence(sequence)
      .raises(Slack::Web::Api::Errors::MissingScope.new("missing_scope"))
    @mock_api_client.expects(:conversations_list)
      .with(exclude_archived: true, limit: 100, types: "public_channel")
      .in_sequence(sequence)
      .returns(slack_message("channels" => [ { "id" => "C123", "name" => "standup-bot-test" } ]))

    channels = @slack_client.list_channels(query: "standup")

    assert_equal [ "C123" ], channels.map { |channel| channel["id"] }
    assert_includes channels.notice, "groups:read"
  end

  test "list_users normalizes users and skips bots and deleted users" do
    @mock_api_client.expects(:users_list)
      .with(limit: 100)
      .returns(slack_message(
        "members" => [
          { "id" => "U123", "name" => "alice", "real_name" => "Alice Doe", "profile" => { "display_name" => "Alice" }, "tz" => "America/New_York" },
          { "id" => "U999", "name" => "bot", "is_bot" => true },
          { "id" => "U888", "name" => "deleted", "deleted" => true }
        ]
      ))

    users = @slack_client.list_users(query: "alice")

    assert_equal 1, users.size
    assert_equal "U123", users.first["id"]
    assert_equal "Alice", users.first["label"]
    assert_equal "America/New_York", users.first["tz"]
  end
end

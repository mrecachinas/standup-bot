require "test_helper"

class SlackClientTest < ActiveSupport::TestCase
  setup do
    SlackClient.reset!
    @slack_client = SlackClient.new
    # Mock the Slack::Web::Client
    @mock_api_client = mock("Slack::Web::Client")
    @slack_client.instance_variable_set(:@client, @mock_api_client)
  end

  test "instance returns a singleton instance" do
    first_instance = SlackClient.instance
    second_instance = SlackClient.instance

    assert_equal first_instance.object_id, second_instance.object_id
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

    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, text: message, as_user: true)
      .returns(expected_response)

    response = @slack_client.send_message(channel, message)
    assert_equal expected_response, response
  end

  test "send_message with blocks" do
    channel = "C12345"
    message = "Hello, world!"
    blocks = [ { type: "section", text: { type: "mrkdwn", text: message } } ]
    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }

    @mock_api_client.expects(:chat_postMessage)
      .with(channel: channel, blocks: blocks, text: message, as_user: true)
      .returns(expected_response)

    response = @slack_client.send_message(channel, message, blocks)
    assert_equal expected_response, response
  end

  test "send_standup_questions" do
    slack_id = "U12345"
    intro = "Time for your daily standup!"
    questions = [ "Question 1", "Question 2" ]

    expected_response = { "ok" => true, "channel" => slack_id, "ts" => "1234567890.123456" }

    @mock_api_client.expects(:chat_postMessage)
      .with(has_entries(channel: slack_id, as_user: true))
      .returns(expected_response)

    result = @slack_client.send_standup_questions(slack_id, intro, questions)

    assert_equal({ channel: expected_response["channel"], ts: expected_response["ts"] }, result)
  end

  test "send_standup_response" do
    channel = "C12345"
    user_name = "John Doe"
    responses = [
      { question: "What did you do yesterday?", answer: "I worked on feature X" },
      { question: "What are you working on today?", answer: "I am working on feature Y" }
    ]

    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }

    @mock_api_client.expects(:chat_postMessage)
      .with(has_entries(channel: channel, as_user: true))
      .returns(expected_response)

    result = @slack_client.send_standup_response(channel, user_name, responses)
    assert_equal expected_response, result
  end

  test "get_user_info successful" do
    slack_id = "U12345"

    # Create a mock user with the expected properties
    mock_user = mock()
    mock_user.stubs(:name).returns("John Doe")
    mock_user.stubs(:tz).returns("America/New_York")
    mock_user.stubs(:tz_offset).returns(-18000)
    mock_user.stubs(:profile).returns({})

    # Create a mock response with the user property
    user_info = mock()
    user_info.stubs(:user).returns(mock_user)

    @mock_api_client.expects(:users_info)
      .with(user: slack_id)
      .returns(user_info)

    result = @slack_client.get_user_info(slack_id)
    assert_equal({ "name" => "John Doe", "tz" => "America/New_York", "tz_offset" => -18000, "profile" => {} }, result)
  end

  test "get_user_info handles user not found" do
    slack_id = "U12345"

    @mock_api_client.expects(:users_info)
      .with(user: slack_id)
      .raises(Slack::Web::Api::Errors::UserNotFound.new("user_not_found"))

    result = @slack_client.get_user_info(slack_id)
    assert_nil result
  end

  test "send_message retries rate limit errors" do
    channel = "C12345"
    message = "Hello, world!"
    expected_response = { "ok" => true, "channel" => channel, "ts" => "1234567890.123456" }

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
      .returns(expected_response)

    assert_equal expected_response, @slack_client.send_message(channel, message)
  end
end

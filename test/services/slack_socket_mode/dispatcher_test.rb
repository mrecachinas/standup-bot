require "test_helper"

class SlackSocketMode::DispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @http = mock("http")
    @dispatcher = SlackSocketMode::Dispatcher.new(http: @http)
    @participant = standup_participants(:one)
    @participant.update!(cached_timezone: "UTC", cached_timezone_updated_at: Time.current)
  end

  test "enqueues permitted event fields and then acks" do
    envelope = {
      "envelope_id" => "env-1",
      "type" => "events_api",
      "payload" => {
        "type" => "event_callback",
        "event" => { "type" => "message", "user" => "U12345", "text" => "hi", "channel" => "D1", "ts" => "1.2", "extra" => "nope" }
      }
    }

    SlackEventProcessorJob.expects(:perform_later).with do |event|
      assert_equal "message", event["type"]
      assert_equal "U12345", event["user"]
      assert_not event.key?("extra")
      true
    end

    assert_equal [ { envelope_id: "env-1" } ], dispatch(envelope)
  end

  test "doesn't ack an event that couldn't be enqueued, so Slack redelivers it" do
    SlackEventProcessorJob.stubs(:perform_later).raises(ActiveRecord::ConnectionNotEstablished)
    envelope = { "envelope_id" => "env-1", "type" => "events_api", "payload" => { "type" => "event_callback", "event" => { "type" => "message" } } }

    acks = []
    assert_raises(ActiveRecord::ConnectionNotEstablished) { @dispatcher.call(envelope) { |ack| acks << ack } }
    assert_empty acks
  end

  test "answers slash commands in the ack payload" do
    envelope = {
      "envelope_id" => "env-2",
      "type" => "slash_commands",
      "payload" => { "command" => "/standup", "text" => "start", "user_id" => @participant.platform_user_id }
    }

    acks = nil
    assert_enqueued_jobs(1, only: StandupMessageJob) { acks = dispatch(envelope) }

    assert_equal "env-2", acks.sole[:envelope_id]
    assert_equal "ephemeral", acks.sole.dig(:payload, :response_type)
    assert_match(/Starting/, acks.sole.dig(:payload, :text))
  end

  test "routes /standup-status by command name" do
    envelope = { "envelope_id" => "env-3", "type" => "slash_commands", "payload" => { "command" => "/standup-status", "user_id" => @participant.platform_user_id } }

    assert_equal SlackInbound.slash_command(:standup_status, user_id: @participant.platform_user_id).body, dispatch(envelope).sole[:payload]
  end

  test "still acks a slash command when handling fails" do
    SlackInbound.stubs(:slash_command).raises(StandardError, "boom")
    envelope = { "envelope_id" => "env-4", "type" => "slash_commands", "payload" => { "command" => "/standup", "user_id" => "U1" } }

    assert_match(/something went wrong/, dispatch(envelope).sole.dig(:payload, :text))
  end

  test "acks interactions first and replies through the response_url" do
    standup = standups(:daily)
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://hooks.slack.com/actions/T1/123/abc",
      "actions" => [ { "action_id" => "standup_selection", "selected_option" => { "value" => standup.id.to_s } } ]
    }
    @http.expects(:post).with do |url, body, headers|
      assert_equal payload["response_url"], url
      assert_match(/Generating report/, JSON.parse(body)["text"])
      assert_equal "application/json", headers["Content-Type"]
      true
    end

    assert_equal [ { envelope_id: "env-5" } ], dispatch({ "envelope_id" => "env-5", "type" => "interactive", "payload" => payload })
  end

  test "won't post interaction replies to a non-Slack URL" do
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://evil.example.com/slack.com",
      "actions" => [ { "action_id" => "unknown" } ]
    }
    @http.expects(:post).never

    dispatch({ "envelope_id" => "env-6", "type" => "interactive", "payload" => payload })
  end

  test "acks unknown envelope types" do
    assert_equal [ { envelope_id: "env-7" } ], dispatch({ "envelope_id" => "env-7", "type" => "something_new" })
  end

  private

  def dispatch(envelope)
    acks = []
    @dispatcher.call(envelope) { |ack| acks << ack }
    acks
  end
end

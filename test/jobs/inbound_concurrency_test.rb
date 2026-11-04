require "test_helper"

# One person's messages and clicks are handled one at a time, in order.
class InboundConcurrencyTest < ActiveSupport::TestCase
  test "Slack messages, edits, and clicks from one person share a concurrency key" do
    message = SlackEventProcessorJob.new({ "type" => "message", "user" => "U1", "text" => "hi" })
    edit = SlackEventProcessorJob.new({ "type" => "message", "subtype" => "message_changed", "message" => { "user" => "U1" } })
    click = SlackInteractionJob.new({ "type" => "block_actions", "user" => { "id" => "U1" } })

    assert_equal [ "chat-inbound/slack:U1" ], [ message, edit, click ].map(&:concurrency_key).uniq
    assert_not_equal message.concurrency_key, SlackEventProcessorJob.new({ "type" => "message", "user" => "U2" }).concurrency_key
  end

  test "Teams activities are keyed by the sender" do
    job = TeamsActivityProcessorJob.new({ "type" => "message", "from" => { "aadObjectId" => "ABC-1" } })

    assert_equal "chat-inbound/teams:abc-1", job.concurrency_key
  end

  test "first messages of a standup are sent a few at a time" do
    assert_equal "StandupMessageJob/send", StandupMessageJob.new("U1", 1).concurrency_key
    assert_equal 2, StandupMessageJob.concurrency_limit
  end
end

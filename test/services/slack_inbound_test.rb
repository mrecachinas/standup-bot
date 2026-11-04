require "test_helper"

class SlackInboundTest < ActiveSupport::TestCase
  test "drops the bot's own messages before enqueueing" do
    SlackEventProcessorJob.expects(:perform_later).never

    SlackInbound.enqueue_event("type" => "message", "user" => "UBOT", "bot_id" => "B1", "app_id" => "A1", "text" => "Hi", "channel" => "D1", "ts" => "1.1")
    SlackInbound.enqueue_event("type" => "message", "subtype" => "bot_message", "bot_id" => "B2", "text" => "Hi", "channel" => "D1", "ts" => "1.2")
    SlackInbound.enqueue_event(
      "type" => "message", "subtype" => "message_changed", "channel" => "D1",
      "message" => { "user" => "UBOT", "bot_id" => "B1", "text" => "Hi there", "ts" => "1.1" },
      "previous_message" => { "user" => "UBOT", "bot_id" => "B1", "text" => "Hi", "ts" => "1.1" }
    )
  end

  test "enqueues people's messages and edits" do
    enqueued = []
    SlackEventProcessorJob.stubs(:perform_later).with { |event| enqueued << event }

    SlackInbound.enqueue_event("type" => "message", "user" => "U1", "text" => "Shipped", "channel" => "D1", "ts" => "1.1")
    SlackInbound.enqueue_event(
      "type" => "message", "subtype" => "message_changed", "channel" => "D1",
      "message" => { "user" => "U1", "text" => "Shipped it", "ts" => "1.1" },
      "previous_message" => { "user" => "U1", "text" => "Shipped", "ts" => "1.1" }
    )

    assert_equal [ "1.1", "1.1" ], [ enqueued.first["ts"], enqueued.second.dig("message", "ts") ]
    assert_equal "Shipped", enqueued.second.dig("previous_message", "text")
  end
end

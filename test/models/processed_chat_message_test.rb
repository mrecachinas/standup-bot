require "test_helper"

class ProcessedChatMessageTest < ActiveSupport::TestCase
  test "runs the block once per message" do
    runs = 0
    2.times { ProcessedChatMessage.process_once(platform: :slack, platform_user_id: "U1", message_id: "1.1") { runs += 1 } }

    assert_equal 1, runs
    assert ProcessedChatMessage.handled?(platform: :slack, platform_user_id: "U1", message_id: "1.1")
  end

  test "a failure leaves the message unhandled, along with anything the block saved" do
    assert_raises(RuntimeError) do
      ProcessedChatMessage.process_once(platform: :slack, platform_user_id: "U1", message_id: "1.2") do
        ProcessedChatMessage.create!(platform: "slack", platform_user_id: "U1", message_id: "saved-by-block")
        raise "boom"
      end
    end

    assert_not ProcessedChatMessage.handled?(platform: :slack, platform_user_id: "U1", message_id: "1.2")
    assert_not ProcessedChatMessage.handled?(platform: :slack, platform_user_id: "U1", message_id: "saved-by-block")
  end

  test "messages without an ID always run" do
    runs = 0
    2.times { ProcessedChatMessage.process_once(platform: :slack, platform_user_id: "U1", message_id: nil) { runs += 1 } }

    assert_equal 2, runs
  end
end

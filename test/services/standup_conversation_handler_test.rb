require "test_helper"

class StandupConversationHandlerTest < ActiveSupport::TestCase
  setup do
    @participant = standup_participants(:one)
    @chat = ChatPlatform.for(:slack)
    @handler = StandupConversationHandler.new(@chat)
  end

  def inbound(text, edited: false)
    ChatPlatform::InboundMessage.new(platform: :slack, user_id: @participant.slack_id, text: text, conversation: "D1", edited: edited)
  end

  test "records an answer for the pending response" do
    response = StandupResponse.create!(standup: @participant.standup, slack_id: @participant.slack_id, status: "pending", answers: [], standup_date: Date.current)

    StandupResponseService.expects(:record_answer).with(response, "Did things")

    @handler.handle(inbound("Did things"))
  end

  test "routes DM commands to DirectMessageCommands with the conversation" do
    DirectMessageCommands.any_instance.expects(:process).with(has_entry(command: :help), @participant.slack_id, "D1")
    StandupResponseService.expects(:record_answer).never

    @handler.handle(inbound("help"))
  end

  test "ignores blank messages" do
    DirectMessageCommands.any_instance.expects(:process).never
    StandupResponseService.expects(:record_answer).never

    @handler.handle(inbound("   "))
  end

  test "edits update the latest pending answer" do
    response = StandupResponse.create!(
      standup: @participant.standup, slack_id: @participant.slack_id, status: "pending", standup_date: Date.current,
      answers: [ { "question" => "Q1", "answer" => "old", "timestamp" => Time.current } ]
    )

    @handler.handle(inbound("new", edited: true))

    assert_equal "new", response.reload.answers.last["answer"]
  end
end

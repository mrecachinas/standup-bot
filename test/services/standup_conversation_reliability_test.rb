require "test_helper"

# Messages delivered twice, sent in quick succession, or arriving when nothing
# is waiting, end to end through the conversation handler.
class StandupConversationReliabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @participant = standup_participants(:one)
    @standup = @participant.standup
    @user_id = @participant.platform_user_id
    @handler = StandupConversationHandler.new(ChatPlatform.for(:slack))
    @t0 = Time.zone.local(2026, 11, 3, 9, 0, 0)
    @sent = []
    StandupResponse.where(platform_user_id: @user_id).delete_all
  end

  # The bot's DMs reach the person at these times, in order.
  def deliver_at(*times)
    refs = times.map { |time| ChatPlatform::MessageRef.new(channel: "D1", id: "bot", sent_at: time) }
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_direct_message).with do |user_id, text|
      @sent << [ user_id, text ]
      true
    end.returns(*refs)
  end

  def dm(text, ts, at)
    ChatPlatform::InboundMessage.new(platform: :slack, user_id: @user_id, text: text, conversation: "D1", edited: false, message_id: ts, sent_at: at)
  end

  def pending_run!(**attributes)
    StandupResponse.create!(standup: @standup, platform_user_id: @user_id, status: "pending", standup_date: Date.current, answers: [], prompted_at: @t0, **attributes)
  end

  test "a message delivered twice is recorded once" do
    run = pending_run!
    deliver_at(@t0 + 10)

    @handler.handle(dm("Shipped it", "100.1", @t0 + 5))
    @handler.handle(dm("Shipped it", "100.1", @t0 + 5))

    assert_equal [ "Shipped it" ], run.reload.answers.map { |answer| answer["answer"] }
    assert_equal 1, @sent.size, "only one next question"
  end

  test "a message sent before the next question showed up continues the previous answer" do
    run = pending_run!
    deliver_at(@t0 + 10, @t0 + 30)

    @handler.handle(dm("foo", "100.1", @t0 + 5))
    # Typed at +7; Q2 reached the person at +10.
    @handler.handle(dm("bar", "100.2", @t0 + 7))
    @handler.handle(dm("Today's work", "100.3", @t0 + 20))

    answers = run.reload.answers
    assert_equal [ "foo\nbar", "Today's work" ], answers.map { |answer| answer["answer"] }
    assert_equal [ "100.1", "100.2" ], answers.first["parts"].map { |part| part["message_id"] }
    assert_equal [ "*What are you doing today?*", "*Any blockers?*" ], @sent.map(&:last)
    assert_equal @t0 + 30, run.prompted_at
  end

  test "a late redelivery is put back in send order" do
    run = pending_run!
    deliver_at(@t0 + 10)

    @handler.handle(dm("second part", "100.2", @t0 + 7))
    @handler.handle(dm("first part", "100.1", @t0 + 5))

    assert_equal "first part\nsecond part", run.reload.answers.first["answer"]
  end

  test "skip right after an answer skips the next question instead of joining the answer" do
    run = pending_run!
    deliver_at(@t0 + 10, @t0 + 12)

    @handler.handle(dm("foo", "100.1", @t0 + 5))
    @handler.handle(dm("skip", "100.2", @t0 + 7))

    assert_equal [ "foo", "(skipped)" ], run.reload.answers.map { |answer| answer["answer"] }
  end

  test "editing one message of a continued answer changes just that part" do
    run = pending_run!
    deliver_at(@t0 + 10)
    @handler.handle(dm("foo", "100.1", @t0 + 5))
    @handler.handle(dm("bar", "100.2", @t0 + 7))

    @handler.handle(ChatPlatform::InboundMessage.new(platform: :slack, user_id: @user_id, text: "baz", conversation: "D1", edited: true, message_id: "100.2", previous_text: "bar"))

    assert_equal "foo\nbaz", run.reload.answers.first["answer"]
  end

  test "a message sent before the sign-off continues the last answer and updates the post" do
    run = pending_run!(answers: [
      { "question" => "What did you do yesterday?", "answer" => "A1", "message_id" => "90.1", "timestamp" => @t0.iso8601 },
      { "question" => "What are you doing today?", "answer" => "A2", "message_id" => "90.2", "timestamp" => @t0.iso8601 }
    ])
    deliver_at(@t0 + 10)
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).returns(ChatPlatform::MessageRef.new(channel: "C1", id: "post.1"))
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update)
      .with(@standup.platform_channel, "post.1", has_entries(answers: [ { question: "What did you do yesterday?", answer: "A1" }, { question: "What are you doing today?", answer: "A2" }, { question: "Any blockers?", answer: "None\nreally none" } ]))

    @handler.handle(dm("None", "100.1", @t0 + 5))
    @handler.handle(dm("really none", "100.2", @t0 + 7))

    assert_equal "completed", run.reload.status
    assert_equal "None\nreally none", run.answers.last["answer"]
    assert_equal 1, @sent.size, "one sign-off"
  end

  test "a message with nothing waiting gets a reply instead of silence" do
    ChatPlatform::SlackAdapter.any_instance.expects(:send_reply)
      .with("D1", responds_with(:text, regexp_matches(/\AThere's no standup waiting on you right now/)))

    @handler.handle(dm("hello?", "100.1", @t0))
  end

  test "a failure while handling leaves the message unhandled, so the retry runs it" do
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_reply).raises(Faraday::ConnectionFailed, "down")

    assert_raises(Faraday::ConnectionFailed) { @handler.handle(dm("hello?", "100.1", @t0 + 5)) }

    assert_not ProcessedChatMessage.handled?(platform: :slack, platform_user_id: @user_id, message_id: "100.1")
  end

  test "a failed send after the answer is saved keeps the answer and retries the question" do
    run = pending_run!
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_direct_message).raises(Faraday::ConnectionFailed, "down")

    assert_enqueued_with(job: StandupPromptJob, args: [ run, 1 ]) do
      @handler.handle(dm("foo", "100.1", @t0 + 5))
    end

    assert_equal [ "foo" ], run.reload.answers.map { |answer| answer["answer"] }
    assert ProcessedChatMessage.handled?(platform: :slack, platform_user_id: @user_id, message_id: "100.1")
  end

  test "a late continuation goes to the question that was showing when it was sent" do
    run = pending_run!
    deliver_at(@t0 + 10, @t0 + 30)
    @handler.handle(dm("foo", "100.1", @t0 + 5))
    @handler.handle(dm("Today's work", "100.3", @t0 + 20))

    # Sent at +7, before Q2 showed up at +10, but delivered after Q2 was answered.
    @handler.handle(dm("bar", "100.2", @t0 + 7))

    assert_equal [ "foo\nbar", "Today's work" ], run.reload.answers.map { |answer| answer["answer"] }
  end

  test "a follow-up while the sign-off is pending continues the last answer" do
    run = pending_run!(status: "completed", prompted_at: @t0, answers: [
      { "question" => "What did you do yesterday?", "answer" => "A1", "message_id" => "90.1", "asked_at" => (@t0 - 60).iso8601(6) },
      { "question" => "What are you doing today?", "answer" => "A2", "message_id" => "90.2", "asked_at" => (@t0 - 30).iso8601(6) },
      { "question" => "Any blockers?", "answer" => "None", "message_id" => "90.3", "asked_at" => @t0.iso8601(6) }
    ])
    run.update_column(:updated_at, @t0 + 5)
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).returns(ChatPlatform::MessageRef.new(channel: "C1", id: "post.1"))

    @handler.handle(dm("really none", "100.1", @t0 + 8))

    assert_equal "None\nreally none", run.reload.answers.last["answer"]
  end
end

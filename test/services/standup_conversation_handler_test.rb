require "test_helper"

class StandupConversationHandlerTest < ActiveSupport::TestCase
  setup do
    @participant = standup_participants(:one)
    @standup = @participant.standup
    @user_id = @participant.platform_user_id
    @chat = ChatPlatform.for(:slack)
    @handler = StandupConversationHandler.new(@chat)
    ChatPlatform::SlackAdapter.any_instance.stubs(:display_name_for).returns("John Doe")
  end

  def inbound(text, edited: false, message_id: nil, previous_text: nil)
    ChatPlatform::InboundMessage.new(
      platform: :slack, user_id: @user_id, text: text, conversation: "D1",
      edited: edited, message_id: message_id, previous_text: previous_text
    )
  end

  def edit(text, message_id: nil, previous_text: nil)
    @handler.handle(inbound(text, edited: true, message_id: message_id, previous_text: previous_text))
  end

  def answer(question, text, message_id = nil)
    { "question" => question, "answer" => text, "timestamp" => 1.hour.ago, "message_id" => message_id }.compact
  end

  def response!(status: "completed", standup: @standup, standup_date: Date.current, answers: [], **attributes)
    StandupResponse.create!(standup: standup, platform_user_id: @user_id, status: status, standup_date: standup_date, answers: answers, **attributes)
  end

  def answer_texts(response)
    response.reload.answers.map { |answer| answer["answer"] }
  end

  test "records an answer with the message ID for the pending response" do
    response = response!(status: "pending")

    StandupResponseService.expects(:record_answer).with(response, "Did things", message_id: "1700.1")

    @handler.handle(inbound("Did things", message_id: "1700.1"))
  end

  test "a skip DM keeps its message ID so it can be edited later" do
    response = response!(status: "pending")
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_direct_message)

    @handler.handle(inbound("skip", message_id: "1700.1"))

    assert_equal [ { "answer" => "(skipped)", "message_id" => "1700.1" } ], response.reload.answers.map { |a| a.slice("answer", "message_id") }
  end

  test "replies to DM commands in the conversation" do
    @chat.expects(:send_reply).with("D1", responds_with(:text, regexp_matches(/Available Commands/)))
    StandupResponseService.expects(:record_answer).never

    @handler.handle(inbound("help"))
  end

  test "ignores blank messages" do
    @chat.expects(:send_reply).never
    StandupResponseService.expects(:record_answer).never

    @handler.handle(inbound("   "))
  end

  test "an edit changes the answer recorded from that message, not another run's" do
    earlier = response!(answers: [ answer("Q1", "Fixed bug", "100.1"), answer("Q2", "Tests", "100.2") ], platform_message_id: "post.1")
    weekdays = standups(:weekdays)
    weekdays.standup_participants.create!(platform_user_id: @user_id, display_name: "John Doe", active: true)
    in_progress = response!(status: "pending", standup: weekdays, answers: [ answer("Priorities?", "Docs", "200.1") ])
    StandupResponseService.expects(:repost_response).with(earlier)

    edit("Fixed two bugs", message_id: "100.1", previous_text: "Fixed bug")

    assert_equal [ "Fixed two bugs", "Tests" ], answer_texts(earlier)
    assert_equal [ "Docs" ], answer_texts(in_progress)
  end

  test "an edit picks the right answer when answers are identical, even for a full rewrite" do
    response = response!(answers: [ answer("Q1", "nothing", "100.1"), answer("Q2", "nothing", "100.2") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).with(response)

    edit("Reviewed PR 264", message_id: "100.2", previous_text: "nothing")

    assert_equal [ "nothing", "Reviewed PR 264" ], answer_texts(response)
  end

  test "an edit updates an earlier answer of the in-progress run" do
    response = response!(status: "pending", answers: [ answer("Q1", "old", "100.1"), answer("Q2", "today", "100.2") ])
    StandupResponseService.expects(:repost_response).never

    edit("new", message_id: "100.1")

    assert_equal [ "new", "today" ], answer_texts(response)
  end

  test "an edit works for a paused standup on an earlier date" do
    @standup.update!(active: false)
    response = response!(standup_date: 3.days.ago.to_date, answers: [ answer("Q1", "old", "100.1") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).with(response)

    edit("new", message_id: "100.1")

    assert_equal [ "new" ], answer_texts(response)
  end

  test "editing a skip fills the answer in and updates the channel post" do
    response = response!(answers: [ answer("Q1", "Shipped", "100.1"), answer("Q2", "(skipped)", "100.2") ], platform_message_id: "post.1")
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update).with(
      @standup.platform_channel, "post.1",
      display_name: "John Doe", standup_name: @standup.name,
      answers: [ { question: "Q1", answer: "Shipped" }, { question: "Q2", answer: "Reviewing" } ]
    )

    edit("Reviewing", message_id: "100.2", previous_text: "skip")

    assert_equal [ "Shipped", "Reviewing" ], answer_texts(response)
  end

  test "editing an answer to skip clears it from the channel post" do
    response = response!(answers: [ answer("Q1", "Shipped", "100.1"), answer("Q2", "Reviewing", "100.2") ], platform_message_id: "post.1")
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update).with(
      @standup.platform_channel, "post.1",
      display_name: "John Doe", standup_name: @standup.name,
      answers: [ { question: "Q1", answer: "Shipped" } ]
    )

    edit("Skip", message_id: "100.2")

    assert_equal [ "Shipped", "(skipped)" ], answer_texts(response)
  end

  test "filling in a finished run that had nothing to post posts it" do
    response = response!(answers: [ answer("Q1", "(skipped)", "100.1"), answer("Q2", "(skipped)", "100.2") ])
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update)
      .with(@standup.platform_channel, display_name: "John Doe", standup_name: @standup.name, answers: [ { question: "Q1", answer: "Shipped" } ])
      .returns(ChatPlatform::MessageRef.new(channel: @standup.platform_channel, id: "post.9"))

    edit("Shipped", message_id: "100.1", previous_text: "skip")

    assert_equal "post.9", response.reload.platform_message_id
  end

  test "editing a skipped run saves the answer without posting" do
    response = response!(status: "skipped", answers: [ answer("Q1", "(skipped)", "100.1") ])
    StandupResponseService.expects(:repost_response).never

    edit("Shipped", message_id: "100.1", previous_text: "skip")

    assert_equal [ "Shipped" ], answer_texts(response)
  end

  test "edits to messages that weren't answers change nothing" do
    response = response!(answers: [ answer("Q1", "Shipped", "100.1"), answer("Q2", "help", "100.2") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).never

    edit("report", message_id: "999.1", previous_text: "help")
    edit("Shipped more", message_id: nil, previous_text: "Shipped")

    assert_equal [ "Shipped", "help" ], answer_texts(response)
  end

  test "edits that don't change the text are ignored" do
    response = response!(answers: [ answer("Q1", "See https://example.com", "100.1") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).never

    edit("See https://example.com", message_id: "100.1", previous_text: "See https://example.com")

    assert_equal [ "See https://example.com" ], answer_texts(response)
  end

  test "edits never touch another person's answers" do
    other = StandupResponse.create!(standup: @standup, platform_user_id: standup_participants(:two).platform_user_id, status: "completed",
      standup_date: Date.current, answers: [ answer("Q1", "theirs", "100.1") ])

    edit("mine", message_id: "100.1", previous_text: "theirs")

    assert_equal [ "theirs" ], answer_texts(other)
  end

  test "edits search recent responses in Ruby, without database JSON functions" do
    inside = response!(standup_date: 59.days.ago.to_date, answers: [ answer("Q1", "old", "100.1") ])
    inside.update_columns(updated_at: 59.days.ago)
    outside = response!(standup_date: 61.days.ago.to_date, answers: [ answer("Q1", "old", "100.2") ])
    outside.update_columns(updated_at: 61.days.ago)
    StandupResponseService.expects(:repost_response).with(inside)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      edit("new", message_id: "100.1")
      edit("new", message_id: "100.2")
    end

    assert_equal [ "new" ], answer_texts(inside)
    assert_equal [ "old" ], answer_texts(outside)
    assert queries.grep(/standup_responses/).any?
    assert_empty queries.grep(/JSON_/i)
  end

  test "answers recorded before message IDs are matched by their exact previous text" do
    older = response!(standup_date: 1.day.ago.to_date, answers: [ answer("Q1", "Fixed bug"), answer("Q2", "Tests") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).with(older)

    edit("Fixed two bugs", message_id: "100.1", previous_text: "Fixed bug")

    assert_equal [ "Fixed two bugs", "Tests" ], answer_texts(older)
  end

  test "an ambiguous previous-text match is skipped" do
    response = response!(answers: [ answer("Q1", "nothing"), answer("Q2", "nothing") ], platform_message_id: "post.1")
    StandupResponseService.expects(:repost_response).never

    edit("Reviewed PR 264", message_id: "100.2", previous_text: "nothing")

    assert_equal [ "nothing", "nothing" ], answer_texts(response)
  end
end

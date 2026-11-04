require "test_helper"

class SlackEventProcessorJobTest < ActiveJob::TestCase
  setup do
    @platform_user_id = "U12345"
    @channel_id = "C12345"

    # Create a pending standup response for testing
    @standup = standups(:daily)
    @participant = standup_participants(:inactive_daily)
    @participant.update!(
      standup: @standup,
      active: true,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )
    @standup_response = StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "pending",
      answers: [],
      created_at: 1.day.ago,
      standup_date: 1.day.ago.to_date
    )
  end

  test "ignores non-message events" do
    event = { "type" => "reaction_added" }

    # Ensure no processing happens for non-message events
    StandupConversationHandler.expects(:new).never

    SlackEventProcessorJob.perform_now(event)
  end

  test "routes messages to commands, pending standup answers, or says nothing is waiting" do
    ChatPlatform::SlackAdapter.any_instance.expects(:send_reply).with(@channel_id, responds_with(:text, regexp_matches(/Available Commands/))).once
    ChatPlatform::SlackAdapter.any_instance.expects(:send_reply)
      .with(@channel_id, responds_with(:text, regexp_matches(/\AThere's no standup waiting on you right now, so I didn't save that\./))).once
    StandupResponseService.expects(:record_answer).with(@standup_response, "I worked on feature X", has_entries(message_id: "1700.2", sent_at: Time.zone.at(1700.2r))).once

    perform_message("help", ts: "1700.1")
    perform_message("I worked on feature X", ts: "1700.2")

    StandupResponse.where(platform_user_id: @platform_user_id).delete_all
    perform_message("Hello world", ts: "1700.3")
  end

  test "ignores the bot's own messages" do
    StandupConversationHandler.expects(:new).never

    SlackEventProcessorJob.perform_now("type" => "message", "user" => "UBOT", "bot_id" => "B1", "text" => "What did you do yesterday?", "channel" => @channel_id, "ts" => "1700.1")
  end

  test "an edit updates the answer recorded from the edited message" do
    @standup_response.update!(status: "completed", platform_message_id: "post.1", answers: [
      { "question" => "Q1", "answer" => "nothing", "timestamp" => Time.current, "message_id" => "1700.1" },
      { "question" => "Q2", "answer" => "nothing", "timestamp" => Time.current, "message_id" => "1700.2" }
    ])
    StandupResponseService.expects(:repost_response).with(@standup_response)

    SlackEventProcessorJob.perform_now(edit_event(ts: "1700.2", text: "Reviewed PR 264", previous_text: "nothing"))

    assert_equal [ "nothing", "Reviewed PR 264" ], @standup_response.reload.answers.map { |answer| answer["answer"] }
  end

  test "an edit to an answer recorded before message IDs matches its previous text" do
    @standup_response.update!(answers: [
      { "question" => "What did you accomplish yesterday?", "answer" => "I worked on feature X", "timestamp" => Time.current }
    ])

    SlackEventProcessorJob.perform_now(edit_event(ts: 1.minute.ago.to_f.to_s, text: "I worked on feature X and also fixed bug Y", previous_text: "I worked on feature X"))

    assert_equal "I worked on feature X and also fixed bug Y", @standup_response.reload.answers.last["answer"]
  end

  test "an edit to a message sent after an old answer was recorded leaves it alone" do
    @standup_response.update!(answers: [ { "question" => "Q1", "answer" => "nothing", "timestamp" => 1.hour.ago } ])

    SlackEventProcessorJob.perform_now(edit_event(ts: Time.current.to_f.to_s, text: "Reviewed PR 264", previous_text: "nothing"))

    assert_equal "nothing", @standup_response.reload.answers.last["answer"]
  end

  test "an edit that matches no recorded answer changes nothing" do
    @standup_response.update!(status: "completed", platform_message_id: "post.1", answers: [
      { "question" => "Q1", "answer" => "I fixed bug A", "timestamp" => Time.current, "message_id" => "1700.1" },
      { "question" => "Q2", "answer" => "I will implement feature B", "timestamp" => Time.current, "message_id" => "1700.2" }
    ])
    StandupResponseService.expects(:repost_response).never

    SlackEventProcessorJob.perform_now(edit_event(ts: "1700.9", text: "I'm also helping with project C", previous_text: "help"))

    assert_equal [ "I fixed bug A", "I will implement feature B" ], @standup_response.reload.answers.map { |answer| answer["answer"] }
  end

  private

  def perform_message(text, ts:)
    SlackEventProcessorJob.perform_now(
      "type" => "message",
      "user" => @platform_user_id,
      "text" => text,
      "channel" => @channel_id,
      "ts" => ts
    )
  end

  def edit_event(ts:, text:, previous_text:)
    {
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => @channel_id,
      "message" => { "user" => @platform_user_id, "text" => text, "ts" => ts },
      "previous_message" => { "user" => @platform_user_id, "text" => previous_text, "ts" => ts }
    }
  end
end

require "test_helper"

class SlackEventWorkflowTest < ActionDispatch::IntegrationTest
  class FakeSlackClient
    attr_reader :messages, :updates

    def initialize
      @messages = []
      @updates = []
      @counter = 0
    end

    def send_message(channel, text, blocks = nil)
      @counter += 1
      @messages << { channel: channel, text: text, blocks: blocks }
      { "ok" => true, "channel" => channel.start_with?("U") ? "D#{channel}" : channel, "ts" => "123.#{@counter}" }
    end

    def get_user_info(slack_id)
      { "name" => slack_id, "profile" => { "display_name" => "Test User" } }
    end

    def update_message(channel, message_ts, text, blocks = nil)
      @updates << { channel: channel, ts: message_ts, text: text, blocks: blocks }
      { "ok" => true, "channel" => channel, "ts" => message_ts }
    end
  end

  setup do
    @standup = standups(:daily)
    @participant = standup_participants(:one)
    @standup.update!(questions: [ "Yesterday?", "Today?", "Blockers?" ], intro: "Time for standup!", outro: "Thanks!")
    StandupResponse.where(slack_id: @participant.slack_id, standup_id: @standup.id).delete_all

    @fake_slack_client = FakeSlackClient.new
    SlackClient.stubs(:instance).returns(@fake_slack_client)
  end

  test "complete standup flow from DM to channel post" do
    StandupMessageJob.perform_now(@participant.slack_id, @standup.id)

    assert_equal @participant.slack_id, @fake_slack_client.messages.first[:channel]

    @standup.questions.each_with_index do |_question, index|
      SlackEventProcessorJob.perform_now(
        "type" => "message",
        "user" => @participant.slack_id,
        "text" => "Answer #{index + 1}",
        "channel" => "D#{@participant.slack_id}"
      )
    end

    response = StandupResponse.where(slack_id: @participant.slack_id, standup_id: @standup.id).last
    assert_equal "completed", response.status
    assert_equal @standup.questions.size, response.answers.size
    assert @fake_slack_client.messages.any? { |message| message[:channel] == @standup.slack_channel }
  end

  test "skip command skips current question and continues workflow" do
    StandupMessageJob.perform_now(@participant.slack_id, @standup.id)

    SlackEventProcessorJob.perform_now(
      "type" => "message",
      "user" => @participant.slack_id,
      "text" => "skip",
      "channel" => "D#{@participant.slack_id}"
    )

    response = StandupResponse.where(slack_id: @participant.slack_id, standup_id: @standup.id).last
    assert_equal "(skipped)", response.answers.first["answer"]
    assert_equal "pending", response.status
  end

  test "edited completed response updates posted channel message" do
    response = StandupResponse.create!(
      standup: @standup,
      slack_id: @participant.slack_id,
      status: "completed",
      answers: [
        { "question" => "Yesterday?", "answer" => "Built workflow", "timestamp" => Time.current },
        { "question" => "Today?", "answer" => "Testing", "timestamp" => Time.current }
      ],
      slack_message_ts: "123.1",
      created_at: Time.current
    )

    SlackEventProcessorJob.perform_now(
      "type" => "message",
      "subtype" => "message_changed",
      "channel" => "D#{@participant.slack_id}",
      "message" => {
        "user" => @participant.slack_id,
        "text" => "Built workflow and slash commands",
        "ts" => "111.222"
      }
    )

    assert_equal "Built workflow and slash commands", response.reload.answers.first["answer"]
    assert_equal 1, @fake_slack_client.updates.size
    assert_equal @standup.slack_channel, @fake_slack_client.updates.first[:channel]
  end
end

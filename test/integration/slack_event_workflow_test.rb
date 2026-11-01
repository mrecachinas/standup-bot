require "test_helper"

class SlackEventWorkflowTest < ActionDispatch::IntegrationTest
  class FakeSlackClient
    attr_reader :messages

    def initialize
      @messages = []
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
    channel_post = @fake_slack_client.messages.find { |message| message[:channel] == @standup.slack_channel }
    assert channel_post
    @standup.questions.each_with_index do |question, index|
      assert_includes channel_post[:text], "*#{question}*\nAnswer #{index + 1}"
    end
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
end

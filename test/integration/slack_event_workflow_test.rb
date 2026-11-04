require "test_helper"

class SlackEventWorkflowTest < ActionDispatch::IntegrationTest
  class FakeSlackClient
    attr_reader :messages

    def initialize
      @messages = []
      @counter = 0
    end

    def send_message(channel, text, blocks = nil, attachments: nil)
      @counter += 1
      @messages << { channel: channel, text: text, blocks: blocks, attachments: attachments }
      { "ok" => true, "channel" => channel.start_with?("U") ? "D#{channel}" : channel, "ts" => "123.#{@counter}" }
    end

    def get_user_info(platform_user_id)
      { "name" => platform_user_id, "profile" => { "display_name" => "Test User" } }
    end
  end

  setup do
    @standup = standups(:daily)
    @participant = standup_participants(:one)
    @standup.update!(questions: [ "Yesterday?", "Today?", "Blockers?" ], intro: "Time for standup!", outro: "Thanks!")
    StandupResponse.where(platform_user_id: @participant.platform_user_id, standup_id: @standup.id).delete_all

    @fake_slack_client = stub_slack_client(FakeSlackClient.new)
  end

  test "complete standup flow from DM to channel post" do
    StandupMessageJob.perform_now(@participant.platform_user_id, @standup.id)

    assert_equal @participant.platform_user_id, @fake_slack_client.messages.first[:channel]

    @standup.questions.each_with_index do |_question, index|
      SlackEventProcessorJob.perform_now(
        "type" => "message",
        "user" => @participant.platform_user_id,
        "text" => "Answer #{index + 1}",
        "channel" => "D#{@participant.platform_user_id}"
      )
    end

    response = StandupResponse.where(platform_user_id: @participant.platform_user_id, standup_id: @standup.id).last
    assert_equal "completed", response.status
    assert_equal @standup.questions.size, response.answers.size
    channel_post = @fake_slack_client.messages.find { |message| message[:channel] == @standup.platform_channel }
    assert channel_post
    # The participant's stored name, without a profile lookup.
    assert_equal "*John Doe* posted an update for *#{@standup.name}*", channel_post[:blocks].first.dig(:text, :text)
    assert_includes channel_post[:text], "*Yesterday?*\nAnswer 1"
    @standup.questions.each_with_index do |question, index|
      assert_equal "*#{question}*\nAnswer #{index + 1}", channel_post[:attachments][index][:blocks].first.dig(:text, :text)
    end
  end

  test "skip command skips current question and continues workflow" do
    StandupMessageJob.perform_now(@participant.platform_user_id, @standup.id)

    SlackEventProcessorJob.perform_now(
      "type" => "message",
      "user" => @participant.platform_user_id,
      "text" => "skip",
      "channel" => "D#{@participant.platform_user_id}"
    )

    response = StandupResponse.where(platform_user_id: @participant.platform_user_id, standup_id: @standup.id).last
    assert_equal "(skipped)", response.answers.first["answer"]
    assert_equal "pending", response.status
  end
end

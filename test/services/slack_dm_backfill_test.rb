require "test_helper"

class SlackDmBackfillTest < ActiveSupport::TestCase
  setup do
    @participant = standup_participants(:one)
    @user_id = @participant.platform_user_id
    StandupResponse.where(platform_user_id: @user_id).delete_all
    @client = stub_slack_client
    @run = StandupResponse.create!(standup: @participant.standup, platform_user_id: @user_id, status: "pending",
      standup_date: Date.current, dm_channel: "D1", created_at: Time.zone.at(1_800_000_000), prompted_at: Time.zone.at(1_800_000_011),
      answers: [ { "question" => "What did you do yesterday?", "answer" => "A1", "message_id" => "1800000010.000100" } ])
    @backfill = SlackDmBackfill.new(client: @client)
  end

  def history(*messages)
    # From the run's start, not its latest answer, so an earlier missed reply is still found.
    @client.expects(:dm_history).with("D1", oldest: "1799999995.000000").returns(messages)
  end

  test "handles replies sent after the latest recorded answer, oldest first, and skips the rest" do
    history(
      { "type" => "message", "user" => @user_id, "text" => "second", "ts" => "1800000030.000100" },
      { "type" => "message", "bot_id" => "B1", "text" => "What are you doing today?", "ts" => "1800000011.000100" },
      { "type" => "message", "user" => "USOMEONE", "text" => "not theirs", "ts" => "1800000025.000100" },
      { "type" => "message", "user" => @user_id, "text" => "first", "ts" => "1800000020.000100" }
    )
    @client.stubs(:send_message).returns({ "channel" => "D1", "ts" => "1800000040.000100" })

    assert_equal 2, @backfill.call(@run)

    # "first" answers Q2. The bot was down, so Q3 only goes out now, after
    # "second" was typed: that continues the Q2 answer.
    assert_equal [ "A1", "first\nsecond" ], @run.reload.answers.map { |answer| answer["answer"] }
  end

  test "skips messages that were already handled" do
    ProcessedChatMessage.create!(platform: "slack", platform_user_id: @user_id, message_id: "1800000020.000100")
    history({ "type" => "message", "user" => @user_id, "text" => "first", "ts" => "1800000020.000100" })

    assert_equal 0, @backfill.call(@run)
    assert_equal [ "A1" ], @run.reload.answers.map { |answer| answer["answer"] }
  end

  test "leaves runs that aren't waiting on a Slack DM alone" do
    @client.expects(:dm_history).never

    @run.update!(status: "completed")
    assert_equal 0, @backfill.call(@run)
  end

  test "leaves runs started before handled messages were recorded alone" do
    @client.expects(:dm_history).never

    @run.update!(prompted_at: nil)
    assert_equal 0, @backfill.call(@run)
  end

  test "skips messages recorded in the person's other runs" do
    other = standups(:weekly)
    other.standup_participants.create!(platform_user_id: @user_id, display_name: "John Doe", active: true)
    StandupResponse.create!(standup: other, platform_user_id: @user_id, status: "completed", standup_date: Date.current,
      answers: [ { "question" => "Q", "answer" => "for the other standup", "message_id" => "1800000020.000100" } ])
    history({ "type" => "message", "user" => @user_id, "text" => "for the other standup", "ts" => "1800000020.000100" })

    assert_equal 0, @backfill.call(@run)
    assert_equal [ "A1" ], @run.reload.answers.map { |answer| answer["answer"] }
  end

  test "replays messages from a long outage into the run, as continuations once the next prompt goes out" do
    @run.update!(answers: @run.answers + [ { "question" => "What are you doing today?", "answer" => "A2", "message_id" => "1800000012.000100" } ])
    history(
      { "type" => "message", "user" => @user_id, "text" => "no blockers", "ts" => "1800003600.000100" },
      { "type" => "message", "user" => @user_id, "text" => "really", "ts" => "1800003610.000100" }
    )
    # The sign-off goes out now, long after both were sent.
    @client.stubs(:send_message).returns({ "channel" => "D1", "ts" => "1800009000.000100" })
    @client.stubs(:update_message)

    assert_equal 2, @backfill.call(@run)

    assert_equal "completed", @run.reload.status
    assert_equal "no blockers\nreally", @run.answers.last["answer"]
  end
end

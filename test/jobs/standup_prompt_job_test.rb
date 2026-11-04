require "test_helper"

class StandupPromptJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @slack = stub_slack_client
    @asked_at = 1.hour.ago.change(usec: 0)
    @run = StandupResponse.create!(standup: @standup, platform_user_id: "UPROMPT", status: "pending", standup_date: Date.current,
      prompted_at: @asked_at, answers: [ { "question" => @standup.questions.first, "answer" => "A1", "asked_at" => @asked_at.iso8601(6) } ])
  end

  test "sends the next question and notes when it went out" do
    @slack.expects(:send_message).with("UPROMPT", "*#{@standup.questions.second}*").returns({ "channel" => "D1", "ts" => "1800000000.000100" })

    StandupPromptJob.perform_now(@run, 1)

    assert_operator @run.reload.prompted_at, :>, @asked_at
  end

  test "sends nothing if the question already went out or the run moved on" do
    @slack.expects(:send_message).never

    @run.update!(prompted_at: 30.minutes.ago)
    StandupPromptJob.perform_now(@run, 1)

    @run.update!(prompted_at: @asked_at)
    StandupPromptJob.perform_now(@run, 2)
  end
end

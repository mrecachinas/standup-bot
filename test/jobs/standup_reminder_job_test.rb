require "test_helper"

class StandupReminderJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @standup.update!(reminder_enabled: true, reminder_after_minutes: 60, max_reminders: 2)
    StandupResponse.where(standup: @standup, status: "pending").delete_all
    @mock_slack_client = mock("SlackClient")
    StandupReminderJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)
  end

  test "sends reminders for overdue pending responses" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      response = StandupResponse.create!(
        standup: @standup,
        slack_id: "UREMIND",
        status: "pending",
        answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ],
        created_at: 2.hours.ago
      )

      @mock_slack_client.expects(:send_message).with("UREMIND", includes("still in progress")).once

      StandupReminderJob.perform_now

      response.reload
      assert_equal 1, response.reminder_count
      assert_not_nil response.last_reminder_at
    end
  end

  test "does not remind before threshold or over max reminders" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UTOOSOON",
        status: "pending",
        answers: [],
        created_at: 30.minutes.ago
      )
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UMAXED",
        status: "pending",
        answers: [],
        reminder_count: 2,
        created_at: 2.hours.ago
      )

      @mock_slack_client.expects(:send_message).never

      StandupReminderJob.perform_now
    end
  end
end

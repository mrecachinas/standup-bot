require "test_helper"

class StandupReminderJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @standup.update!(reminder_enabled: true, reminder_after_minutes: 60, max_reminders: 2)
    StandupResponse.where(standup: @standup, status: "pending").delete_all
    @mock_slack_client = stub_slack_client
  end

  test "sends reminders for overdue pending responses" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      response = StandupResponse.create!(
        standup: @standup,
        platform_user_id: "UREMIND",
        status: "pending",
        answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ],
        created_at: 2.hours.ago
      )

      @mock_slack_client.expects(:send_message).with(
        "UREMIND",
        "⏰ *Daily Standup* is still waiting on you (1 of 3 answered). Reply here to pick up where you left off, or `skip` to pass on this one.\n\n*#{@standup.questions.second}*"
      ).once

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
        platform_user_id: "UTOOSOON",
        status: "pending",
        answers: [],
        created_at: 30.minutes.ago
      )
      StandupResponse.create!(
        standup: @standup,
        platform_user_id: "UMAXED",
        status: "pending",
        answers: [],
        reminder_count: 2,
        created_at: 2.hours.ago
      )

      @mock_slack_client.expects(:send_message).never

      StandupReminderJob.perform_now
    end
  end

  test "does not remind paused standups or cancelled standup dates" do
    Timecop.freeze(Time.zone.local(2026, 5, 1, 12, 0, 0)) do
      paused_response = StandupResponse.create!(
        standup: @standup,
        platform_user_id: "UPAUSED",
        status: "pending",
        answers: [],
        standup_date: Date.new(2026, 5, 1),
        created_at: 2.hours.ago
      )
      @standup.update!(active: false)

      @mock_slack_client.expects(:send_message).never
      StandupReminderJob.perform_now(@standup.id)

      assert_equal 0, paused_response.reload.reminder_count

      @standup.update!(active: true)
      @standup.standup_schedule_exceptions.create!(
        exception_type: "cancelled",
        original_date: Date.new(2026, 5, 1)
      )

      StandupReminderJob.perform_now(@standup.id)
      assert_equal 0, paused_response.reload.reminder_count
    end
  end

  test "a failed reminder is given back for the next run and doesn't stop the others" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      failing = StandupResponse.create!(standup: @standup, platform_user_id: "UFAIL", status: "pending", answers: [], created_at: 2.hours.ago, standup_date: Date.current)
      other = StandupResponse.create!(standup: @standup, platform_user_id: "UOTHER", status: "pending", answers: [], created_at: 2.hours.ago, standup_date: Date.current)
      @mock_slack_client.expects(:send_message).with("UFAIL", anything).raises(Slack::Web::Api::Errors::SlackError.new("account_inactive"))
      @mock_slack_client.expects(:send_message).with("UOTHER", anything).once

      StandupReminderJob.perform_now

      assert_equal 0, failing.reload.reminder_count
      assert_nil failing.last_reminder_at
      assert_equal 1, other.reload.reminder_count
    end
  end

  test "counts from the latest prompt, so a new question isn't reminded about right away" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(standup: @standup, platform_user_id: "UPROMPTED", status: "pending", answers: [], created_at: 2.hours.ago, prompted_at: 10.minutes.ago, standup_date: Date.current)
      @mock_slack_client.expects(:send_message).never

      StandupReminderJob.perform_now
    end
  end

  test "skips the reminder when the person's DM had replies the bot missed" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      response = StandupResponse.create!(standup: @standup, platform_user_id: "UMISSED", status: "pending", answers: [], created_at: 2.hours.ago, dm_channel: "D9", standup_date: Date.current)
      SlackDmBackfill.any_instance.expects(:call).with(response).returns(1)
      @mock_slack_client.expects(:send_message).never

      StandupReminderJob.perform_now

      assert_equal 0, response.reload.reminder_count
    end
  end

  test "a reminder claimed by a worker that stopped before sending is tried again later" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      # Claimed an interval ago, never sent: the count wasn't used up.
      response = StandupResponse.create!(standup: @standup, platform_user_id: "UABANDON", status: "pending", answers: [],
        created_at: 3.hours.ago, last_reminder_at: 61.minutes.ago, reminder_count: 0, standup_date: Date.current)
      @mock_slack_client.expects(:send_message).with("UABANDON", anything).once

      StandupReminderJob.perform_now

      assert_equal 1, response.reload.reminder_count
    end
  end

  test "an answer saved while the DM history is checked cancels the reminder" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      response = StandupResponse.create!(standup: @standup, platform_user_id: "URACE", status: "pending", answers: [],
        created_at: 2.hours.ago, prompted_at: 2.hours.ago, dm_channel: "D9", standup_date: Date.current)
      SlackDmBackfill.any_instance.expects(:call).with do
        # Another worker records the answer and sends the next question meanwhile.
        StandupResponse.find(response.id).update!(answers: [ { "question" => @standup.questions.first, "answer" => "Done" } ], prompted_at: Time.current)
        true
      end.returns(0)
      @mock_slack_client.expects(:send_message).never

      StandupReminderJob.perform_now

      assert_equal 0, response.reload.reminder_count
      assert_nil response.last_reminder_at
    end
  end
end

require "test_helper"

class ParticipantReactivationJobTest < ActiveJob::TestCase
  setup do
    # Use fixtures instead of creating records
    @participant1 = standup_participants(:inactive_daily)
    @participant2 = standup_participants(:inactive_weekly)

    # Make sure they're inactive for our test cases, with away periods ending today
    @participant1.update!(active: false, vacation_until: Date.current)
    @participant2.update!(active: false, vacation_until: Date.current)

    # Get common platform_user_id from the fixtures
    @platform_user_id = @participant1.platform_user_id

    @mock_slack_client = stub_slack_client

    # Reference the standups from the participants
    @standup1 = @participant1.standup
    @standup2 = @participant2.standup
  end

  test "reactivates all participants for the user" do
    # Expect notification to be sent
    @mock_slack_client.expects(:send_message)
      .with(@platform_user_id, "Welcome back! You've been automatically re-enabled for standups.")
      .once

    # Run the job
    ParticipantReactivationJob.perform_now(@platform_user_id)

    # Verify that participants were reactivated
    @participant1.reload
    @participant2.reload

    assert @participant1.active
    assert @participant2.active
  end

  test "does nothing when no inactive participants found" do
    # Activate all participants before running the test
    StandupParticipant.update_all(active: true)

    # No notification should be sent
    @mock_slack_client.expects(:send_message).never

    # Run the job
    ParticipantReactivationJob.perform_now(@platform_user_id)

    # Verify that participants remain active
    @participant1.reload
    @participant2.reload

    assert @participant1.active
    assert @participant2.active
  end

  test "handles users with no participants" do
    # Delete all participants for this user
    StandupParticipant.where(platform_user_id: @platform_user_id).delete_all

    # No notification should be sent
    @mock_slack_client.expects(:send_message).never

    # No error should be raised
    assert_nothing_raised do
      ParticipantReactivationJob.perform_now(@platform_user_id)
    end
  end

  test "a job for an earlier date doesn't end a later away period, and checks again on that date" do
    @mock_slack_client.expects(:send_message).never
    # Away until the 10th, then back early and away again (or a manager moved the date) until the 20th.
    @participant1.update!(vacation_until: Date.new(2026, 11, 20), cached_timezone: "America/New_York", cached_timezone_updated_at: Time.current)

    assert_enqueued_with(
      job: ParticipantReactivationJob,
      args: [ @platform_user_id, [ @participant1.id ], "slack", "2026-11-20" ],
      # The day after the new last day away.
      at: Time.find_zone("America/New_York").local(2026, 11, 21)
    ) do
      ParticipantReactivationJob.perform_now(@platform_user_id, [ @participant1.id ], "slack", "2026-11-10")
    end

    assert_not @participant1.reload.active?
    assert_equal Date.new(2026, 11, 20), @participant1.vacation_until
  end

  test "a job leaves rows paused without an away date alone" do
    @mock_slack_client.expects(:send_message).never
    @participant1.update!(vacation_until: nil)

    ParticipantReactivationJob.perform_now(@platform_user_id, [ @participant1.id ], "slack", "2026-11-10")

    assert_not @participant1.reload.active?
  end

  test "a job reactivates rows whose away period it ends" do
    @mock_slack_client.expects(:send_message).once
    @participant1.update!(vacation_until: Date.new(2026, 11, 10))

    ParticipantReactivationJob.perform_now(@platform_user_id, [ @participant1.id ], "slack", "2026-11-10")

    assert @participant1.reload.active?
    assert_nil @participant1.vacation_until
  end

  test "a job queued before away dates were passed only ends away periods that are over" do
    @mock_slack_client.expects(:send_message).once
    @participant2.update!(vacation_until: Date.current + 5, cached_timezone: "UTC", cached_timezone_updated_at: Time.current)

    ParticipantReactivationJob.perform_now(@platform_user_id, [ @participant1.id, @participant2.id ], "slack")

    assert @participant1.reload.active?
    assert_not @participant2.reload.active?
  end
end

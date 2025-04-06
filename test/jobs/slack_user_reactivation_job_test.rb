require "test_helper"

class SlackUserReactivationJobTest < ActiveJob::TestCase
  setup do
    # Use fixtures instead of creating records
    @participant1 = standup_participants(:inactive_daily)
    @participant2 = standup_participants(:inactive_weekly)

    # Make sure they're inactive for our test cases
    @participant1.update!(active: false)
    @participant2.update!(active: false)

    # Get common slack_id from the fixtures
    @slack_id = @participant1.slack_id

    # Create mock slack client
    @mock_slack_client = mock("SlackClient")
    SlackUserReactivationJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)

    # Reference the standups from the participants
    @standup1 = @participant1.standup
    @standup2 = @participant2.standup
  end

  test "reactivates all participants for the user" do
    # Expect notification to be sent
    @mock_slack_client.expects(:send_message)
      .with(@slack_id, "Welcome back! You've been automatically re-enabled for standups.")
      .once

    # Run the job
    SlackUserReactivationJob.perform_now(@slack_id)

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
    SlackUserReactivationJob.perform_now(@slack_id)

    # Verify that participants remain active
    @participant1.reload
    @participant2.reload

    assert @participant1.active
    assert @participant2.active
  end

  test "handles users with no participants" do
    # Delete all participants for this user
    StandupParticipant.where(slack_id: @slack_id).delete_all

    # No notification should be sent
    @mock_slack_client.expects(:send_message).never

    # No error should be raised
    assert_nothing_raised do
      SlackUserReactivationJob.perform_now(@slack_id)
    end
  end
end

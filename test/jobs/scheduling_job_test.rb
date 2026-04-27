require "test_helper"

class SchedulingJobTest < ActiveJob::TestCase
  setup do
    @active_standup = standups(:daily)
    @inactive_standup = standups(:inactive)
    @participant = standup_participants(:one) # Using 'one' fixture instead of 'active_participant'
    @inactive_participant = standup_participants(:inactive)

    # Make sure our test standup is active
    @active_standup.update(active: true)
    @inactive_standup.update(active: false)

    # Associate participant with the active standup
    @participant.update(
      standup_id: @active_standup.id,
      active: true,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )

    # Mock time calculation for consistency
    @scheduled_time = Time.new(2025, 4, 7, 9, 0, 0, "+00:00")
    @standup_date = @scheduled_time.to_date
    StandupParticipant.any_instance.stubs(:calculate_send_time).returns(@scheduled_time)
    StandupParticipant.any_instance.stubs(:standup_date_for).returns(@standup_date)
  end

  test "schedules messages for active standups only" do
    # First clear out any unexpected participants from fixtures to ensure
    # we have a controlled environment
    StandupParticipant.where.not(id: [ @participant.id, @inactive_participant.id ]).delete_all

    # First test: active standup should have job scheduled
    assert_enqueued_with(
      job: StandupMessageJob,
      at: @scheduled_time,
      args: [ @participant.slack_id, @active_standup.id, @standup_date.iso8601 ]
    ) do
      SchedulingJob.perform_now
    end

    # Reset the job queue to start fresh
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    # Ensure the inactive standup exists and is saved
    assert @inactive_standup.persisted?

    # Update the inactive participant to be associated with the inactive standup
    @inactive_participant.standup = @inactive_standup
    @inactive_participant.active = true  # Even though this participant is active...
    @inactive_participant.save!

    # Remove active participants to isolate our test
    @participant.destroy!

    # Also make sure no other active participants exist for ANY standup
    StandupParticipant.where.not(id: @inactive_participant.id).delete_all

    # Verify we only have participants for the inactive standup
    participant_count = StandupParticipant.count
    inactive_standup_participant_count = StandupParticipant.where(standup_id: @inactive_standup.id).count
    assert_equal participant_count, inactive_standup_participant_count,
      "Expected all participants to be for the inactive standup"

    # Now run SchedulingJob and verify no jobs are scheduled for inactive standups
    assert_no_enqueued_jobs(only: StandupMessageJob) do
      SchedulingJob.perform_now
    end
  end

  test "schedules messages for active participants only" do
    # First, remove any other active participants to control our test environment
    StandupParticipant.where.not(id: [ @participant.id, @inactive_participant.id ]).delete_all

    # Create an inactive participant
    @inactive_participant.standup = @active_standup
    @inactive_participant.save!

    # Verify we only have one active participant with the active standup
    active_count = StandupParticipant.where(active: true, standup_id: @active_standup.id).count
    assert_equal 1, active_count, "Expected only one active participant but found #{active_count}"

    # Check that message is scheduled only for active participants
    assert_enqueued_jobs 1, only: StandupMessageJob do
      SchedulingJob.perform_now
    end
  end

  test "calculates correct time for each participant" do
    # Test that the job uses the participant's calculated send time
    send_at = @participant.calculate_send_time

    assert_enqueued_with(
      job: StandupMessageJob,
      at: send_at,
      args: [ @participant.slack_id, @active_standup.id, @standup_date.iso8601 ]
    ) do
      SchedulingJob.perform_now
    end
  end

  test "does not schedule participants on vacation" do
    StandupParticipant.where.not(id: @participant.id).delete_all
    @participant.update!(vacation_until: @standup_date)

    assert_no_enqueued_jobs(only: StandupMessageJob) do
      SchedulingJob.perform_now
    end
  end

  test "does not schedule standups on holidays" do
    StandupParticipant.where.not(id: @participant.id).delete_all
    Standup.any_instance.stubs(:skips_occurrence_on?).with(@standup_date).returns(true)

    assert_no_enqueued_jobs(only: StandupMessageJob) do
      SchedulingJob.perform_now
    end
  end

  test "schedules rescheduled occurrence using original standup date" do
    StandupParticipant.where.not(id: @participant.id).delete_all
    original_date = Date.new(2026, 5, 1)
    rescheduled_at = Time.zone.local(2026, 5, 1, 10, 15)
    occurrence = Standup::Occurrence.new(
      standup_date: original_date,
      scheduled_at: rescheduled_at,
      status: "rescheduled"
    )

    StandupParticipant.any_instance.stubs(:calculate_send_time).returns(rescheduled_at)
    StandupParticipant.any_instance.stubs(:next_standup_occurrence).returns(occurrence)

    Timecop.freeze(Time.zone.local(2026, 5, 1, 9, 30)) do
      assert_enqueued_with(
        job: StandupMessageJob,
        at: rescheduled_at,
        args: [ @participant.slack_id, @active_standup.id, original_date.iso8601 ]
      ) do
        SchedulingJob.perform_now
      end
    end
  end

  test "does not schedule duplicate when same-day response has nil standup date" do
    StandupParticipant.where.not(id: @participant.id).delete_all
    response = StandupResponse.create!(
      standup: @active_standup,
      slack_id: @participant.slack_id,
      status: "pending",
      answers: [],
      created_at: @scheduled_time
    )
    response.update_column(:standup_date, nil)

    assert_no_enqueued_jobs(only: StandupMessageJob) do
      SchedulingJob.perform_now
    end
  end
end

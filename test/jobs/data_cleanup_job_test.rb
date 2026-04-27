require "test_helper"
require "timecop"

class DataCleanupJobTest < ActiveJob::TestCase
  setup do
    @previous_retention_days = ENV["RESPONSE_RETENTION_DAYS"]
    @previous_stale_days = ENV["STALE_PENDING_DAYS"]
    @previous_batch_size = ENV["CLEANUP_BATCH_SIZE"]
    ENV["RESPONSE_RETENTION_DAYS"] = "30"
    ENV["STALE_PENDING_DAYS"] = "7"
    ENV["CLEANUP_BATCH_SIZE"] = "2"
    @standup = standups(:daily)
  end

  teardown do
    ENV["RESPONSE_RETENTION_DAYS"] = @previous_retention_days
    ENV["STALE_PENDING_DAYS"] = @previous_stale_days
    ENV["CLEANUP_BATCH_SIZE"] = @previous_batch_size
  end

  test "deletes old responses and expires stale pending responses" do
    Timecop.freeze(Time.zone.local(2025, 6, 1, 12, 0, 0)) do
      old_response = StandupResponse.create!(
        standup: @standup,
        slack_id: "UOLD",
        status: "completed",
        answers: [],
        created_at: 31.days.ago,
        updated_at: 31.days.ago
      )
      stale_pending = StandupResponse.create!(
        standup: @standup,
        slack_id: "USTALE",
        status: "pending",
        answers: [],
        created_at: 8.days.ago,
        updated_at: 8.days.ago
      )
      fresh_pending = StandupResponse.create!(
        standup: @standup,
        slack_id: "UFRESH",
        status: "pending",
        answers: [],
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      result = DataCleanupJob.perform_now

      assert result[:old_responses_deleted].positive?
      assert_not StandupResponse.exists?(old_response.id)
      assert_equal "expired", stale_pending.reload.status
      assert_equal "pending", fresh_pending.reload.status
    end
  end
end

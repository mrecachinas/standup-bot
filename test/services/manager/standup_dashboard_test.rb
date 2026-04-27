require "test_helper"

module Manager
  class StandupDashboardTest < ActiveSupport::TestCase
    setup do
      @standup = standups(:daily)
    end

    test "builds display labels for dashboard cards" do
      standup_participants(:one).update!(cached_timezone: "America/New_York", cached_timezone_updated_at: Time.current)

      item = StandupDashboard.new([ @standup ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0)).items.first

      assert_equal @standup, item.standup
      assert_equal "Active", item.status_label
      assert_equal "Daily at 09:00", item.cadence_label
      assert_equal "America/New_York", item.timezone_label
      assert_equal 2, item.participant_count
    end

    test "summarizes latest run status from newest response date" do
      now = Time.zone.local(2026, 4, 27, 12, 0, 0)
      StandupResponse.create!(
        standup: @standup,
        slack_id: "ULATE1",
        status: "completed",
        answers: [],
        created_at: now - 20.minutes,
        updated_at: now - 10.minutes
      )
      StandupResponse.create!(
        standup: @standup,
        slack_id: "ULATE2",
        status: "pending",
        answers: [],
        created_at: now - 15.minutes
      )

      item = StandupDashboard.new([ @standup ], period_days: 1, now: now).items.first

      assert_equal "Pending", item.latest_run_status
      assert_includes item.latest_run_detail, "1 completed"
      assert_includes item.latest_run_detail, "1 pending"
    end

    test "shows no run copy without responses" do
      standup = standups(:inactive)
      item = StandupDashboard.new([ standup ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0)).items.first

      assert_equal "Paused", item.status_label
      assert_equal "No runs yet", item.latest_run_status
      assert_equal "No responses have been collected yet", item.latest_run_detail
    end
  end
end

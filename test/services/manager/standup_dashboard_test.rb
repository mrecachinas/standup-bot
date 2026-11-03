require "test_helper"

module Manager
  class StandupDashboardTest < ActiveSupport::TestCase
    setup do
      @standup = standups(:daily)
    end

    test "builds display data for dashboard rows" do
      item = StandupDashboard.new([ @standup ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0)).items.first

      assert_equal @standup, item.standup
      assert_equal "Active", item.status_label
      assert_equal 2, item.participant_count
      assert_equal item.participant_count, item.participant_names.size
      assert_equal item.runs.map { |run| run[:completion_rate] }, item.trend_rates
    end

    test "flags paused and low-completion standups for attention" do
      paused = StandupDashboard.new([ standups(:inactive) ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0)).items.first

      assert paused.needs_attention?
      assert_equal "Paused", paused.attention_reason
    end

    test "summarizes latest run status from newest response date" do
      now = Time.zone.local(2026, 4, 27, 12, 0, 0)
      StandupResponse.create!(
        standup: @standup,
        platform_user_id: "ULATE1",
        status: "completed",
        answers: [],
        created_at: now - 20.minutes,
        updated_at: now - 10.minutes
      )
      StandupResponse.create!(
        standup: @standup,
        platform_user_id: "ULATE2",
        status: "pending",
        answers: [],
        created_at: now - 15.minutes
      )

      item = StandupDashboard.new([ @standup ], period_days: 1, now: now).items.first

      assert_equal "Pending", item.latest_run_status
      assert_equal "Apr 27 · 1 of 2 answered", item.latest_run_summary
    end

    test "shows no run copy without responses" do
      standup = standups(:inactive)
      item = StandupDashboard.new([ standup ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0)).items.first

      assert_equal "Paused", item.status_label
      assert_equal "No runs yet", item.latest_run_status
      assert_nil item.latest_run_summary
    end

    test "doesn't flag a standup created today for low completion" do
      now = Time.zone.local(2026, 4, 27, 12, 0, 0)
      standup = Standup.create!(name: "Brand new", platform_channel: "brand-new", questions: [ "Update?" ], schedule_type: "daily", created_at: now - 2.hours)
      %w[UNEW00001 UNEW00002 UNEW00003].each do |platform_user_id|
        standup.standup_participants.create!(platform_user_id: platform_user_id, display_name: platform_user_id, active: true, created_at: now - 2.hours)
      end

      item = StandupDashboard.new([ standup ], now: now).items.first

      assert_equal 0, item.expected_responses
      assert_not item.needs_attention?
    end

    test "counts people once even when they're in several standups" do
      shared = standup_participants(:one)
      standups(:weekly).standup_participants.create!(platform_user_id: shared.platform_user_id, display_name: shared.display_name, active: true)

      dashboard = StandupDashboard.new([ @standup, standups(:weekly) ], period_days: 1, now: Time.zone.local(2026, 4, 27, 12, 0, 0))

      assert_equal dashboard.items.sum(&:participant_count) - 1, dashboard.people_count
    end
  end
end

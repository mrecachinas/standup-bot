require "test_helper"
require "timecop"

class StandupAnalyticsServiceTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
  end

  test "builds completion summary" do
    Timecop.freeze(Time.zone.local(2025, 4, 6, 12, 0, 0)) do
      summary = StandupAnalyticsService.new(@standup, period_days: 1).summary

      assert_equal @standup.id, summary[:standup_id]
      assert summary[:expected_responses].positive?
      assert summary[:completed_responses].positive?
      assert summary.key?(:completion_rate)
      assert summary[:participant_stats].any?
    end
  end

  test "counts monthly day 31 schedules on shorter month end" do
    standup = standups(:weekly)
    standup.update!(schedule_type: "monthly", schedule_days: [ 31 ])

    Timecop.freeze(Time.zone.local(2025, 3, 31, 12, 0, 0)) do
      summary = StandupAnalyticsService.new(standup, period_days: 31).summary

      assert_equal 2, summary[:expected_responses]
      assert_equal 2, summary[:participant_stats].first[:expected]
      assert_equal 0.0, summary[:completion_rate]
    end
  end

  test "response trends use month end fallback for monthly schedules" do
    standup = standups(:weekly)
    standup.update!(schedule_type: "monthly", schedule_days: [ 31 ])

    Timecop.freeze(Time.zone.local(2025, 3, 31, 12, 0, 0)) do
      trends = StandupAnalyticsService.new(standup, period_days: 31).response_trends
      expected_by_date = trends.index_by { |entry| entry[:date] }.transform_values do |entry|
        entry[:expected]
      end

      assert_equal 1, expected_by_date["2025-02-28"]
      assert_equal 0, expected_by_date["2025-03-30"]
      assert_equal 1, expected_by_date["2025-03-31"]
    end
  end

  test "extracts blocker keywords" do
    StandupResponse.create!(
      standup: @standup,
      slack_id: "U999BLOCK",
      status: "completed",
      answers: [
        { "question" => "Any blockers?", "answer" => "Waiting on review and deployment review" }
      ],
      created_at: Time.current
    )

    keywords = StandupAnalyticsService.new(@standup, period_days: 1).blocker_keywords

    assert_includes keywords.map { |entry| entry[:keyword] }, "review"
  end
end

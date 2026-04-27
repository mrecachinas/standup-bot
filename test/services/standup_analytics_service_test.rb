require "test_helper"
require "csv"
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

  test "date range trends summarize selected days" do
    analytics = StandupAnalyticsService.new(
      @standup,
      start_date: "2025-04-06",
      end_date: "2025-04-06"
    )

    assert_equal Date.new(2025, 4, 6), analytics.start_date
    assert_equal Date.new(2025, 4, 6), analytics.end_date

    trend = analytics.response_trends.first
    assert_equal "2025-04-06", trend[:date]
    assert_equal 2, trend[:expected]
    assert_equal 1, trend[:completed]
    assert_equal 50.0, trend[:completion_rate]
  end

  test "frequent non responders rank missed expected responses" do
    analytics = StandupAnalyticsService.new(
      @standup,
      start_date: "2025-04-06",
      end_date: "2025-04-06"
    )

    non_responder = analytics.frequent_non_responders.first

    assert_equal "U234567", non_responder[:slack_id]
    assert_equal "Jane Smith", non_responder[:slack_name]
    assert_equal 1, non_responder[:missed]
    assert_equal 0.0, non_responder[:completion_rate]
  end

  test "summary includes average response time" do
    @standup.standup_participants.create!(slack_id: "UAVG160", slack_name: "Average User")
    response = StandupResponse.create!(
      standup: @standup,
      slack_id: "UAVG160",
      status: "completed",
      answers: [ { "question" => "Any blockers?", "answer" => "No blockers" } ],
      standup_date: Date.new(2025, 4, 8),
      created_at: Time.zone.local(2025, 4, 8, 9, 0, 0)
    )
    response.update_column(:updated_at, Time.zone.local(2025, 4, 8, 9, 45, 0))

    summary = StandupAnalyticsService.new(
      @standup,
      start_date: "2025-04-08",
      end_date: "2025-04-08"
    ).summary

    assert_equal 45.0, summary[:average_response_time_minutes]
  end

  test "question summaries include answer rates keywords and latest answers" do
    summaries = StandupAnalyticsService.new(
      @standup,
      start_date: "2025-04-06",
      end_date: "2025-04-06"
    ).question_summaries

    yesterday_summary = summaries.find { |summary| summary[:question] == "What did you do yesterday?" }
    blocker_summary = summaries.find { |summary| summary[:question] == "Any blockers?" }

    assert_equal 1, yesterday_summary[:answered]
    assert_equal 100.0, yesterday_summary[:answer_rate]
    assert_equal "Fixed bugs", yesterday_summary[:latest_answers].first[:answer]
    assert_equal 1, blocker_summary[:answered]
    assert_empty blocker_summary[:common_keywords]
  end

  test "csv export includes selected date range rows and misses" do
    csv = StandupAnalyticsService.new(
      @standup,
      start_date: "2025-04-07",
      end_date: "2025-04-07"
    ).to_csv

    parsed = CSV.parse(csv, headers: true)

    assert_equal StandupAnalyticsService::CSV_HEADERS, parsed.headers
    assert_equal [ "2025-04-07" ], parsed.map { |row| row["Date"] }.uniq
    assert_includes parsed.map { |row| row["Status"] }, "Missed"
    assert_includes parsed.map { |row| row["Participant"] }, "John Doe"
    assert_not_includes parsed.map { |row| row["Answer"] }, "Fixed bugs"
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

  test "schedule exceptions adjust expected report counts" do
    @standup.standup_schedule_exceptions.create!(
      exception_type: "holiday",
      original_date: Date.new(2026, 5, 1),
      reason: "Company holiday"
    )
    @standup.standup_schedule_exceptions.create!(
      exception_type: "rescheduled",
      original_date: Date.new(2026, 5, 2),
      rescheduled_date: Date.new(2026, 5, 2),
      rescheduled_time: "11:30",
      rescheduled_timezone: "UTC"
    )

    holiday_summary = StandupAnalyticsService.new(
      @standup,
      start_date: "2026-05-01",
      end_date: "2026-05-01"
    ).summary
    rescheduled_summary = StandupAnalyticsService.new(
      @standup,
      start_date: "2026-05-02",
      end_date: "2026-05-02"
    ).summary

    assert_equal 0, holiday_summary[:expected_responses]
    assert_equal @standup.standup_participants.active.count, rescheduled_summary[:expected_responses]
  end
end

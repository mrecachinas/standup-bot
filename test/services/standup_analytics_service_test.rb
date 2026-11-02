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

    # The day after, so the Mar 31 run has already gone out.
    Timecop.freeze(Time.zone.local(2025, 4, 1, 12, 0, 0)) do
      summary = StandupAnalyticsService.new(standup, period_days: 33).summary

      assert_equal 2, summary[:expected_responses]
      assert_equal 2, summary[:participant_stats].first[:expected]
      assert_equal 0.0, summary[:completion_rate]
    end
  end

  test "response trends use month end fallback for monthly schedules" do
    standup = standups(:weekly)
    standup.update!(schedule_type: "monthly", schedule_days: [ 31 ])

    Timecop.freeze(Time.zone.local(2025, 4, 1, 12, 0, 0)) do
      trends = StandupAnalyticsService.new(standup, period_days: 33).response_trends
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

  test "summary includes average response time" do
    @standup.standup_participants.create!(platform_user_id: "UAVG160", display_name: "Average User")
    response = StandupResponse.create!(
      standup: @standup,
      platform_user_id: "UAVG160",
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
      platform_user_id: "U999BLOCK",
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
  test "participants who responded before a later vacation still count as expected" do
    participant = @standup.standup_participants.active.first
    @standup.standup_responses.delete_all

    Timecop.freeze(Time.zone.local(2025, 4, 10, 12, 0, 0)) do
      @standup.standup_responses.create!(platform_user_id: participant.platform_user_id, status: "completed", standup_date: Date.new(2025, 4, 9), answers: [])
      participant.update!(vacation_until: Date.new(2025, 4, 20))

      analytics = StandupAnalyticsService.new(@standup, start_date: "2025-04-09", end_date: "2025-04-09")
      stat = analytics.participant_stats.find { |entry| entry[:platform_user_id] == participant.platform_user_id }

      assert_equal 1, stat[:expected]
      assert_in_delta 100.0, stat[:completion_rate]
      assert_operator analytics.completion_rate, :<=, 100
    end
  end

  test "run breakdown lists each scheduled run with status counts" do
    participants = @standup.standup_participants.active.order(:platform_user_id).to_a
    @standup.standup_responses.delete_all
    @standup.standup_responses.create!(platform_user_id: participants[0].platform_user_id, status: "completed", standup_date: Date.new(2025, 4, 9), answers: [])
    @standup.standup_responses.create!(platform_user_id: participants[1].platform_user_id, status: "skipped", standup_date: Date.new(2025, 4, 9), answers: [])

    runs = StandupAnalyticsService.new(@standup, start_date: "2025-04-08", end_date: "2025-04-09").run_breakdown
    run = runs.find { |entry| entry[:date] == Date.new(2025, 4, 9) }

    assert_equal [ Date.new(2025, 4, 8), Date.new(2025, 4, 9) ], runs.map { |entry| entry[:date] }
    assert_equal 1, run[:completed]
    assert_equal 1, run[:skipped]
    assert_equal participants.size - 2, run[:missed]
  end
  test "completion stays at or below 100 percent after a responder is deactivated" do
    participants = @standup.standup_participants.active.order(:platform_user_id).first(2)
    @standup.standup_responses.delete_all
    [ Date.new(2025, 4, 8), Date.new(2025, 4, 9) ].each do |date|
      participants.each do |participant|
        @standup.standup_responses.create!(platform_user_id: participant.platform_user_id, status: "completed", standup_date: date, answers: [])
      end
    end
    participants.last.update!(active: false)

    analytics = StandupAnalyticsService.new(@standup, start_date: "2025-04-08", end_date: "2025-04-09")

    assert_operator analytics.completion_rate, :<=, 100
    assert(analytics.run_breakdown.all? { |run| run[:completion_rate] <= 100 })
    assert_equal 4, analytics.summary[:completed_responses]
  end

  test "reports whether any responses exist in the range" do
    @standup.standup_responses.delete_all

    assert_not StandupAnalyticsService.new(@standup, start_date: "2025-04-08", end_date: "2025-04-09").responses?
  end
  test "question funnel shows where started check-ins stop" do
    @standup.update!(questions: [ "Yesterday?", "Today?", "Blockers?" ])
    participants = @standup.standup_participants.active.order(:platform_user_id).first(2)
    @standup.standup_responses.delete_all
    date = Date.new(2025, 4, 9)
    @standup.standup_responses.create!(platform_user_id: participants[0].platform_user_id, standup_date: date, status: "completed", answers: [
      { "question" => "Yesterday?", "answer" => "Shipped" },
      { "question" => "Today?", "answer" => "(skipped)" },
      { "question" => "Blockers?", "answer" => "None" }
    ])
    @standup.standup_responses.create!(platform_user_id: participants[1].platform_user_id, standup_date: date, status: "expired", answers: [
      { "question" => "Yesterday?", "answer" => "Reviews" }
    ])
    @standup.standup_responses.create!(platform_user_id: "UINPROGRESS", standup_date: date, status: "pending", answers: [
      { "question" => "Yesterday?", "answer" => "Still typing" }
    ])

    funnel = StandupAnalyticsService.new(@standup, start_date: "2025-04-09", end_date: "2025-04-09").question_funnel

    assert_equal [ 2, 2, 2 ], funnel.map { |row| row[:started] }
    assert_equal [ 2, 0, 1 ], funnel.map { |row| row[:answered] }
    assert_equal [ 0, 1, 0 ], funnel.map { |row| row[:skipped] }
    assert_equal [ 0, 1, 1 ], funnel.map { |row| row[:not_reached] }
    assert_equal [ 0, 1, 0 ], funnel.map { |row| row[:drop_off] }
  end

  test "a run that hasn't gone out yet isn't counted as missed" do
    participants = @standup.standup_participants.active.order(:platform_user_id).to_a
    @standup.standup_responses.delete_all
    @standup.standup_responses.create!(platform_user_id: participants[0].platform_user_id, status: "pending", standup_date: Date.new(2025, 4, 10), answers: [])

    Timecop.freeze(Time.zone.local(2025, 4, 10, 8, 0, 0)) do
      analytics = StandupAnalyticsService.new(@standup, start_date: "2025-04-09", end_date: "2025-04-10")
      today = analytics.run_breakdown.find { |run| run[:date] == Date.new(2025, 4, 10) }

      assert_equal 1, today[:expected]
      assert_equal 1, today[:pending]
      assert_equal 0, today[:missed]
      assert_equal participants.size + 1, analytics.summary[:expected_responses]
    end

    @standup.standup_responses.delete_all
    Timecop.freeze(Time.zone.local(2025, 4, 10, 8, 0, 0)) do
      runs = StandupAnalyticsService.new(@standup, start_date: "2025-04-09", end_date: "2025-04-10").run_breakdown

      assert_equal [ Date.new(2025, 4, 9) ], runs.map { |run| run[:date] }
    end
  end
end


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

  test "a standup created mid-window only expects runs since it was created" do
    standup = new_daily_standup(created_at: Time.zone.local(2025, 4, 8, 8, 0, 0))
    standup.standup_responses.create!(platform_user_id: "UNEW00001", status: "completed", standup_date: Date.new(2025, 4, 8), answers: [])
    standup.standup_responses.create!(platform_user_id: "UNEW00002", status: "expired", standup_date: Date.new(2025, 4, 8), answers: [])
    standup.standup_responses.create!(platform_user_id: "UNEW00001", status: "completed", standup_date: Date.new(2025, 4, 9), answers: [])

    Timecop.freeze(Time.zone.local(2025, 4, 10, 12, 0, 0)) do
      analytics = StandupAnalyticsService.new(standup, period_days: 14)
      summary = analytics.summary

      assert_equal 4, summary[:expected_responses]
      assert_equal 2, summary[:completed_responses]
      assert_in_delta 50.0, summary[:completion_rate]
      assert_equal [ Date.new(2025, 4, 8), Date.new(2025, 4, 9) ], analytics.run_breakdown.map { |run| run[:date] }
      assert_equal [ 2, 2 ], summary[:participant_stats].map { |stat| stat[:expected] }
    end
  end

  test "a standup created today has nothing expected yet" do
    now = Time.zone.local(2025, 4, 10, 15, 0, 0)
    standup = new_daily_standup(created_at: now - 1.hour)

    Timecop.freeze(now) do
      summary = StandupAnalyticsService.new(standup, period_days: 30).summary

      assert_equal 0, summary[:expected_responses]
      assert_equal 0.0, summary[:completion_rate]
      assert(summary[:participant_stats].all? { |stat| stat[:expected].zero? })
    end
  end

  test "the day a standup was created only counts for people who got a prompt" do
    # Created after that day's 9:00 run had already gone out.
    standup = new_daily_standup(created_at: Time.zone.local(2025, 4, 8, 14, 0, 0))

    Timecop.freeze(Time.zone.local(2025, 4, 10, 12, 0, 0)) do
      trends = StandupAnalyticsService.new(standup, start_date: "2025-04-07", end_date: "2025-04-09").response_trends

      assert_equal [ 0, 0, 2 ], trends.map { |trend| trend[:expected] }
    end

    standup.standup_responses.create!(platform_user_id: "UNEW00001", status: "pending", standup_date: Date.new(2025, 4, 8), answers: [])

    Timecop.freeze(Time.zone.local(2025, 4, 10, 12, 0, 0)) do
      trends = StandupAnalyticsService.new(standup, start_date: "2025-04-07", end_date: "2025-04-09").response_trends

      assert_equal [ 0, 1, 2 ], trends.map { |trend| trend[:expected] }
    end
  end

  test "a participant added mid-window is only expected from when they joined" do
    @standup.standup_responses.delete_all
    newcomer = @standup.standup_participants.create!(platform_user_id: "UJOINED01", display_name: "New Person", active: true)
    newcomer.update_column(:created_at, Time.zone.local(2025, 4, 8, 12, 0, 0))

    Timecop.freeze(Time.zone.local(2025, 4, 10, 12, 0, 0)) do
      analytics = StandupAnalyticsService.new(@standup, start_date: "2025-04-06", end_date: "2025-04-09")
      stats = analytics.participant_stats.index_by { |stat| stat[:platform_user_id] }

      assert_equal 1, stats["UJOINED01"][:expected]
      assert_equal 4, stats["U123456"][:expected]
      assert_equal 4, stats["U234567"][:expected]
      assert_equal 9, analytics.summary[:expected_responses]

      csv = CSV.parse(analytics.to_csv, headers: true)
      newcomer_rows = csv.select { |row| row["User ID"] == "UJOINED01" }
      assert_equal [ "2025-04-09" ], newcomer_rows.map { |row| row["Date"] }
    end
  end

  test "join dates use the participant's standup timezone" do
    standup = new_daily_standup(created_at: Time.zone.local(2025, 4, 1, 0, 0, 0), respect_timezone: true)
    participant = standup.standup_participants.find_by!(platform_user_id: "UNEW00001")
    participant.update_columns(cached_timezone: "Asia/Tokyo", cached_timezone_updated_at: 1.year.ago, created_at: Time.zone.local(2025, 4, 8, 20, 0, 0))
    StandupParticipant.any_instance.expects(:fetch_profile).never

    Timecop.freeze(Time.zone.local(2025, 4, 12, 12, 0, 0)) do
      stats = StandupAnalyticsService.new(standup, start_date: "2025-04-07", end_date: "2025-04-11").participant_stats.index_by { |stat| stat[:platform_user_id] }

      # 20:00 UTC on Apr 8 is already Apr 9 in Tokyo, so Apr 10 and 11 count.
      assert_equal 2, stats["UNEW00001"][:expected]
      assert_equal 5, stats["UNEW00002"][:expected]
    end
  end

  private

  def new_daily_standup(created_at:, respect_timezone: false)
    standup = Standup.create!(
      name: "Brand new",
      platform_channel: "brand-new",
      questions: [ "Update?" ],
      schedule_type: "daily",
      default_hour: 9,
      default_minute: 0,
      respect_timezone: respect_timezone,
      created_at: created_at
    )
    %w[UNEW00001 UNEW00002].each do |platform_user_id|
      standup.standup_participants.create!(platform_user_id: platform_user_id, display_name: platform_user_id, active: true, created_at: created_at)
    end
    standup
  end
end

require "test_helper"
require "csv"

class Api::AnalyticsInsightsTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "requires authentication" do
    get api_standup_analytics_path(@owned_standup, view: "insights"), as: :json

    assert_response :unauthorized
  end

  test "manager views insights for an owned standup" do
    sign_in(@manager, "manager-access-token")

    get api_standup_analytics_path(@owned_standup, view: "insights", start_date: "2025-04-06", end_date: "2025-04-06"), as: :json

    assert_response :success
    body = response.parsed_body
    insights = body["insights"]
    assert_equal @owned_standup.name, body.dig("standup", "name")
    assert_equal "2025-04-06", insights.dig("range", "start_date")
    assert_equal "2025-04-06", insights.dig("range", "end_date")
    assert_equal 1, insights.dig("range", "days")
    assert_equal [ 7, 30, 90 ], insights.dig("range", "presets").map { |preset| preset["days"] }
    assert insights["has_data"]
    assert insights["stats"].key?("completion_rate")
    assert insights["stats"].key?("completion_rate_delta")
    assert_equal "vs. the previous 1 day", insights.dig("stats", "comparison_label")
    assert_equal 1, insights.dig("stats", "runs_count")
    assert_equal [ "2025-04-06" ], insights["runs"].map { |run| run["date"] }
    assert_equal insights["runs"].size, insights["completion_series"].size

    jane = insights["participants"].find { |participant| participant["name"] == "Jane Smith" }
    assert_equal "1 missed response", jane["missed_label"]
    assert_equal "danger", jane["rate_tone"]
    assert_equal insights["participants"].map { |participant| participant["completion_rate"] }.sort, insights["participants"].map { |participant| participant["completion_rate"] }

    answers = insights["question_summaries"].flat_map { |question| question["latest_answers"].map { |answer| answer["answer"] } }
    assert_includes answers, "Fixed bugs"
    assert_equal @owned_standup.questions, insights.dig("question_funnel", "rows").map { |row| row["question"] }
    assert insights.dig("question_funnel", "started_label").start_with?("Out of ")
    assert_includes body["csv_path"], api_standup_analytics_path(@owned_standup, format: :csv)

    # The admin API's analytics payload rides along for the same range.
    assert body["analytics"].key?("response_trends")
    assert body["analytics"].key?("blocker_keywords")
  end

  test "compares completion with the previous period" do
    @owned_standup.standup_responses.create!(platform_user_id: "U234567", status: "completed", answers: [], standup_date: Date.new(2025, 4, 5), created_at: Time.zone.local(2025, 4, 5, 10))
    sign_in(@manager, "manager-access-token")

    get api_standup_analytics_path(@owned_standup, view: "insights", start_date: "2025-04-06", end_date: "2025-04-06"), as: :json

    stats = response.parsed_body.dig("insights", "stats")
    assert_not_nil stats["previous_completion_rate"]
    assert_equal (stats["completion_rate"] - stats["previous_completion_rate"]).round, stats["completion_rate_delta"]
    assert_includes %w[up down flat], stats["completion_rate_delta_direction"]
  end

  test "date filters exclude analytics outside the selected range" do
    @owned_standup.standup_participants.create!(platform_user_id: "UFILTER160", display_name: "Filter User")
    StandupResponse.create!(
      standup: @owned_standup,
      platform_user_id: "UFILTER160",
      status: "completed",
      answers: [ { "question" => "Any blockers?", "answer" => "Outside analytics range" } ],
      standup_date: Date.new(2025, 4, 5),
      created_at: Time.zone.local(2025, 4, 5, 9, 0, 0)
    )
    sign_in(@manager, "manager-access-token")

    get api_standup_analytics_path(@owned_standup, view: "insights", start_date: "2025-04-06", end_date: "2025-04-06"), as: :json

    assert_response :success
    assert_not_includes response.body, "Outside analytics range"
  end

  test "csv export downloads the selected range with the session cookie" do
    sign_in(@manager, "manager-access-token")

    get api_standup_analytics_path(@owned_standup, format: :csv), params: { start_date: "2025-04-07", end_date: "2025-04-07" }

    assert_response :success
    assert_includes response.media_type, "text/csv"
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "daily-standup-analytics-2025-04-07-2025-04-07.csv"

    parsed = CSV.parse(response.body, headers: true)
    assert_equal StandupAnalyticsService::CSV_HEADERS, parsed.headers
    assert_equal [ "2025-04-07" ], parsed.map { |row| row["Date"] }.uniq
    assert_includes parsed.map { |row| row["Status"] }, "Missed"
    assert_includes parsed.map { |row| row["Participant"] }, "Jane Smith"
    assert_not_includes parsed.map { |row| row["Answer"] }, "Fixed bugs"
  end

  test "csv export works with an admin's token" do
    get api_standup_analytics_path(@unowned_standup, format: :csv), params: { start_date: "2025-04-06", end_date: "2025-04-06" }, headers: token_headers

    assert_response :success
    assert_includes response.media_type, "text/csv"
    assert_includes response.body, "Complete project X"
  end

  test "manager can't view or export analytics for a standup they don't own" do
    sign_in(@manager, "manager-access-token")

    get api_standup_analytics_path(@unowned_standup, view: "insights"), as: :json
    assert_response :forbidden

    get api_standup_analytics_path(@unowned_standup, format: :csv), params: { start_date: "2025-04-06", end_date: "2025-04-06" }
    assert_response :forbidden
    assert_not_includes response.body, "Complete project X"
  end

  test "admin can view insights for any standup" do
    sign_in(@admin, "admin-access-token")

    get api_standup_analytics_path(@unowned_standup, view: "insights", start_date: "2025-04-06", end_date: "2025-04-06"), as: :json

    assert_response :success
    assert_equal @unowned_standup.name, response.parsed_body.dig("standup", "name")
    assert_includes response.body, "Complete project X"
  end

  test "an admin's token gets insights too" do
    get api_standup_analytics_path(@unowned_standup, view: "insights"), headers: token_headers, as: :json

    assert_response :success
    assert response.parsed_body.key?("insights")
  end

  test "without view=insights the admin API payload is unchanged" do
    get api_standup_analytics_path(@owned_standup, period_days: 30), headers: token_headers, as: :json

    assert_response :success
    assert_equal [ "analytics" ], response.parsed_body.keys
  end

  test "stats keep their contract" do
    sign_in(@manager, "manager-access-token")

    get api_standup_stats_path(@owned_standup), as: :json

    assert_response :success
    assert_equal [ "stats" ], response.parsed_body.keys
    assert_equal @owned_standup.id, response.parsed_body.dig("stats", "standup_id")

    get api_standup_stats_path(@unowned_standup), as: :json
    assert_response :forbidden
  end
end

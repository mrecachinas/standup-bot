require "test_helper"
require "csv"

class Manager::StandupAnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "requires authentication" do
    get manager_standup_analytics_path(@owned_standup)

    assert_redirected_to new_session_path
  end

  test "manager views analytics insights for owned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_analytics_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_includes response.body, "Insights for #{@owned_standup.name}"
    assert_includes response.body, "Completion trends over time"
    assert_includes response.body, "Frequent non-responders"
    assert_includes response.body, "Average response time"
    assert_includes response.body, "Question-level summaries"
    assert_includes response.body, "Jane Smith"
    assert_includes response.body, "1 missed response"
    assert_includes response.body, "Fixed bugs"
    assert_includes response.body, "Export CSV"
    assert_includes response.body, manager_standup_responses_path(@owned_standup)
  end

  test "date filters exclude analytics outside selected range" do
    @owned_standup.standup_participants.create!(slack_id: "UFILTER160", slack_name: "Filter User")
    StandupResponse.create!(
      standup: @owned_standup,
      slack_id: "UFILTER160",
      status: "completed",
      answers: [ { "question" => "Any blockers?", "answer" => "Outside analytics range" } ],
      standup_date: Date.new(2025, 4, 5),
      created_at: Time.zone.local(2025, 4, 5, 9, 0, 0)
    )
    sign_in(@manager, "manager-access-token")

    get manager_standup_analytics_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_not_includes response.body, "Outside analytics range"
  end

  test "csv export includes selected range shape and content" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_analytics_path(@owned_standup, format: :csv),
      params: { start_date: "2025-04-07", end_date: "2025-04-07" }

    assert_response :success
    assert_includes response.media_type, "text/csv"

    parsed = CSV.parse(response.body, headers: true)
    assert_equal StandupAnalyticsService::CSV_HEADERS, parsed.headers
    assert_equal [ "2025-04-07" ], parsed.map { |row| row["Date"] }.uniq
    assert_includes parsed.map { |row| row["Status"] }, "Missed"
    assert_includes parsed.map { |row| row["Participant"] }, "Jane Smith"
    assert_not_includes parsed.map { |row| row["Answer"] }, "Fixed bugs"
  end

  test "manager cannot view or export analytics for unowned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_analytics_path(@unowned_standup)
    assert_response :forbidden

    get manager_standup_analytics_path(@unowned_standup, format: :csv),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :forbidden
    assert_not_includes response.body, "Complete project X"
  end

  test "admin can view analytics for any standup" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_analytics_path(@unowned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_includes response.body, "Insights for #{@unowned_standup.name}"
    assert_includes response.body, "Complete project X"
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

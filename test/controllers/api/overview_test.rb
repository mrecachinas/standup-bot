require "test_helper"

# GET /api/overview: the console's home page across the standups someone manages.
class Api::OverviewTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @inactive_standup = standups(:inactive)
  end

  test "requires authentication" do
    get api_overview_path, as: :json

    assert_response :unauthorized
  end

  test "manager sees only owned standups" do
    sign_in(@manager, "manager-access-token")

    get api_overview_path, as: :json

    assert_response :success
    names = response.parsed_body["standups"].map { |row| row["name"] }
    assert_includes names, @owned_standup.name
    assert_not_includes names, @unowned_standup.name
  end

  test "dashboard returns metrics, status, and rows" do
    sign_in(@manager, "manager-access-token")

    Timecop.freeze(Time.zone.local(2026, 4, 27, 12, 0, 0)) do
      StandupResponse.create!(
        standup: @owned_standup,
        platform_user_id: "UDASHBOARD1",
        status: "completed",
        answers: [],
        created_at: 30.minutes.ago,
        updated_at: Time.current
      )
      StandupResponse.create!(
        standup: @owned_standup,
        platform_user_id: "UDASHBOARD2",
        status: "pending",
        answers: [],
        created_at: 20.minutes.ago
      )

      get api_overview_path(period_days: 1), as: :json
    end

    assert_response :success
    body = response.parsed_body
    assert_equal %w[
      daily_has_pending daily_totals empty empty_list_message needs_attention needs_attention_empty_message
      period_days standups stats subtitle visibility visibility_options
    ], body.keys.sort
    assert_equal 1, body["period_days"]
    assert_equal "all", body["visibility"]
    assert_equal "How your standups are doing over the last 1 day.", body["subtitle"]
    assert_equal false, body["empty"]

    row = body["standups"].sole
    assert_equal @owned_standup.id, row["id"]
    assert_equal "Every day at 9:00 AM", row["schedule_summary"]
    assert_equal 2, row["participant_count"]
    assert_equal "2 active participants", row["participant_label"]
    assert_equal [ "Jane Smith", "John Doe" ], row["participant_avatars"].map { |avatar| avatar["name"] }
    # The completed response counts toward expected so the rate can't exceed
    # 100%. Today's run hasn't reached John or Jane yet, so it isn't held against them.
    assert_in_delta 33.3, row["completion_rate"]
    assert_equal "33%", row["completion_rate_label"]
    assert_equal "danger", row["completion_tone"]
    assert_equal "1 of 3 responses", row["completion_sub_label"]
    assert_equal "Pending", row["latest_run_status"]
    assert_equal "info", row["latest_run_status_tone"]
    assert row["latest_run_pending"]
    assert_equal "Apr 27 · 1 of 2 answered", row["latest_run_summary"]
    assert row["trend_rates"].is_a?(Array)
    assert row.dig("next_run", "label").start_with?("Next in ")
    assert row.dig("next_run", "scheduled_at").present?
    assert_equal "Active", row["status_label"]
    assert row["needs_attention"]
    assert_equal "33% completion over 1 days", row["attention_reason"]

    stats = body["stats"]
    assert_equal 1, stats["active_count"]
    assert_equal "None paused", stats["paused_label"]
    assert_equal 2, stats["people_count"]
    assert_equal "Across 1 standup", stats["people_label"]
    assert_equal "33%", stats["completion_rate_label"]
    assert_equal "1 of 3 expected", stats["completion_sub_label"]
    assert_equal 1, stats["needs_attention_count"]
    assert_equal "1 under 60%", stats["needs_attention_label"]

    assert body["daily_has_pending"]
    assert_equal "2026-04-27", body["daily_totals"].last["date"]
    assert_equal({ "standup_id" => @owned_standup.id, "name" => @owned_standup.name, "active" => true, "reason" => "33% completion over 1 days", "tone" => "danger" }, body["needs_attention"].sole)
  end

  test "visibility filter can focus active or paused standups" do
    sign_in(@manager, "manager-access-token")
    @owned_standup.update!(active: false)

    get api_overview_path(visibility: "active"), as: :json
    assert_response :success
    assert_empty response.parsed_body["standups"]
    assert_equal false, response.parsed_body["empty"]
    assert_equal "No active standups.", response.parsed_body["empty_list_message"]

    get api_overview_path(visibility: "paused"), as: :json
    assert_response :success
    row = response.parsed_body["standups"].sole
    assert_equal @owned_standup.name, row["name"]
    assert_equal "Paused", row["status_label"]
    assert_equal "warning", row["status_tone"]
    assert_equal "Not scheduled", row.dig("next_run", "label")
    assert_equal "Paused", row["attention_reason"]
  end

  test "an unknown visibility falls back to all and period days are clamped" do
    sign_in(@admin, "admin-access-token")

    get api_overview_path(visibility: "bogus", period_days: 500), as: :json

    assert_response :success
    assert_equal "all", response.parsed_body["visibility"]
    assert_equal 90, response.parsed_body["period_days"]
  end

  test "admin sees paused standups" do
    sign_in(@admin, "admin-access-token")

    get api_overview_path(visibility: "paused"), as: :json

    assert_response :success
    assert_includes response.parsed_body["standups"].map { |row| row["name"] }, @inactive_standup.name
    attention = response.parsed_body["needs_attention"].find { |item| item["standup_id"] == @inactive_standup.id }
    assert_equal "warning", attention["tone"]
  end

  test "a manager with no standups gets the empty state" do
    StandupOwnership.where(user: @manager).delete_all
    sign_in(@manager, "manager-access-token")

    get api_overview_path, as: :json

    assert_response :success
    assert response.parsed_body["empty"]
    assert_empty response.parsed_body["standups"]
  end

  test "an admin's token sees every standup" do
    get api_overview_path, headers: { "Authorization" => "Bearer admin-access-token" }, as: :json

    assert_response :success
    assert_equal Standup.count, response.parsed_body["standups"].size
  end

  private

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end
end

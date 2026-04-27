require "test_helper"

class Api::StandupManagementControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_token = "test-admin-token"
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = @admin_token
    @standup = standups(:daily)
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "manages participants" do
    get api_standup_participants_path(@standup), headers: admin_headers
    assert_response :success
    assert JSON.parse(response.body)["participants"].any?

    assert_difference "@standup.standup_participants.count", 1 do
      post api_standup_participants_path(@standup),
        params: { participant: { slack_id: "UADMIN1", slack_name: "Admin User", active: true } },
        headers: admin_headers,
        as: :json
    end

    assert_response :created
    participant_id = JSON.parse(response.body).dig("participant", "id")

    assert_difference "@standup.standup_participants.count", -1 do
      delete api_standup_participant_path(@standup, participant_id), headers: admin_headers
    end

    assert_response :no_content
  end

  test "lists responses with filters" do
    get api_standup_responses_path(@standup, status: "completed", limit: 10), headers: admin_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body["responses"].all? { |standup_response| standup_response["status"] == "completed" }
  end

  test "returns stats and analytics" do
    get api_standup_stats_path(@standup, period_days: 30), headers: admin_headers
    assert_response :success
    stats = JSON.parse(response.body)["stats"]
    assert_equal @standup.id, stats["standup_id"]
    assert stats.key?("completion_rate")

    get api_standup_analytics_path(@standup, period_days: 30), headers: admin_headers
    assert_response :success
    analytics = JSON.parse(response.body)["analytics"]
    assert analytics.key?("response_trends")
    assert analytics.key?("blocker_keywords")
  end

  private

  def admin_headers
    { "Authorization" => "Bearer #{@admin_token}" }
  end
end

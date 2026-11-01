require "test_helper"

class Api::AdminDashboardTest < ActionDispatch::IntegrationTest
  ADMIN_TOKEN = "test-admin-token".freeze

  setup do
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = ADMIN_TOKEN
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "requires authentication" do
    get api_admin_dashboard_path, as: :json

    assert_response :unauthorized
  end

  test "managers can't view the admin dashboard" do
    sign_in(users(:manager), "manager-access-token")

    get api_admin_dashboard_path, as: :json

    assert_response :forbidden
  end

  test "admins see installation health, users, and recent changes" do
    sign_in(users(:admin), "admin-access-token")
    AuditLog.create!(action: "standup.update", actor: users(:admin), auditable: standups(:daily))

    get api_admin_dashboard_path, as: :json

    assert_response :success
    body = response.parsed_body
    assert_includes %w[healthy degraded unhealthy], body.dig("health", "status")
    assert body.dig("health", "checked_at").present?
    assert_equal %w[database job_queue slack_api teams_api], body["health_checks"].map { |check| check["key"] }
    assert_equal [ "Database", "Job queue", "Slack", "Microsoft Teams" ], body["health_checks"].map { |check| check["label"] }
    database = body["health_checks"].first
    assert_equal "Operational", database["status_label"]
    assert_equal [ "Adapter", "Latency" ], database["details"].map { |detail| detail["label"] }

    assert_equal Standup.count, body.dig("stats", "standups_total")
    assert_equal User.active.count, body.dig("stats", "users_active")
    assert_equal 14, body["activity_days"]
    assert_equal StandupResponse.count, body.dig("response_totals", "total")

    manager = body["users"].find { |user| user["email"] == users(:manager).email }
    assert_equal "Member", manager["access_label"]
    assert_equal users(:manager).email, manager["subtitle"]
    admin = body["users"].find { |user| user["email"] == users(:admin).email }
    assert_equal "All", admin["owned_standups_label"]

    log = body["audit_logs"].find { |entry| entry["action"] == "standup.update" }
    assert_equal "standup update", log["action_label"]
    assert_equal users(:admin).name, log["actor_name"]
    assert_equal "Standup ##{standups(:daily).id}", log["auditable_label"]
  end

  test "failed report deliveries are listed" do
    sign_in(users(:admin), "admin-access-token")

    get api_admin_dashboard_path, as: :json

    report = response.parsed_body["failed_reports"].find { |entry| entry["id"] == report_generations(:failed_daily_report).id }
    assert_equal standups(:daily).name, report["standup_name"]
    assert_equal "Slack API timeout", report["error_message"]
  end

  test "recent response activity is charted per day" do
    standups(:daily).standup_responses.create!(platform_user_id: "U234567", status: "completed", answers: [], standup_date: Date.current)
    sign_in(users(:admin), "admin-access-token")

    get api_admin_dashboard_path, as: :json

    today = response.parsed_body["daily_activity"].find { |row| row["date"] == Date.current.iso8601 }
    assert_operator today["completed"], :>=, 1
    assert today["title"].present?
  end

  test "the token is an admin" do
    get api_admin_dashboard_path, headers: { "Authorization" => "Bearer #{ADMIN_TOKEN}" }, as: :json

    assert_response :success
  end

  private

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end
end

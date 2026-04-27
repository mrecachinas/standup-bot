require "test_helper"

class Api::StandupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_token = "test-admin-token"
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = @admin_token
    @standup = standups(:daily)
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "requires bearer token" do
    get api_standups_path
    assert_response :unauthorized
  end

  test "does not expose admin endpoints when token is unconfigured" do
    ENV.delete("ADMIN_API_TOKEN")

    get api_standups_path
    assert_response :service_unavailable
  end

  test "lists standups" do
    get api_standups_path, headers: admin_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body["standups"].any? { |standup| standup["id"] == @standup.id }
    assert body["standups"].first.key?("active_participants_count")
  end

  test "creates standup" do
    assert_difference "Standup.count", 1 do
      post api_standups_path,
        params: {
          standup: {
            name: "Admin Created",
            slack_channel: "admin-created",
            questions: [ "What changed?", "Any blockers?" ],
            schedule_type: "daily",
            default_hour: 9,
            default_minute: 15,
            respect_timezone: true,
            active: true
          }
        },
        headers: admin_headers,
        as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Admin Created", body.dig("standup", "name")
  end

  test "updates standup" do
    assert_difference "AuditLog.where(action: 'standup.update', actor_label: 'admin_api').count", 1 do
      patch api_standup_path(@standup),
        params: { standup: { name: "Updated Name", active: false } },
        headers: admin_headers,
        as: :json
    end

    assert_response :success
    assert_equal "Updated Name", @standup.reload.name
    assert_not @standup.active
  end

  test "deletes standup" do
    standup = Standup.create!(
      name: "Temporary Standup",
      slack_channel: "temporary",
      questions: [ "Question?" ],
      schedule_type: "daily",
      respect_timezone: true
    )

    assert_difference "Standup.count", -1 do
      delete api_standup_path(standup), headers: admin_headers
    end

    assert_response :no_content
  end

  private

  def admin_headers
    { "Authorization" => "Bearer #{@admin_token}" }
  end
end

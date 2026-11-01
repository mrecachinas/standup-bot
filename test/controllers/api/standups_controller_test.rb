require "test_helper"

class Api::StandupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_token = "admin-access-token"
    @standup = standups(:daily)
  end

  test "requires bearer token" do
    get api_standups_path
    assert_response :unauthorized
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
            platform_channel: "admin-created",
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
    assert_equal "slack", body.dig("standup", "platform")
    assert_equal "admin-created", body.dig("standup", "platform_channel")
    assert_not body["standup"].key?("slack_channel")
  end

  test "rejects changing a standup's platform" do
    patch api_standup_path(@standup),
      params: { standup: { platform: "other" } },
      headers: admin_headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal "slack", @standup.reload.platform
  end

  test "updates standup" do
    assert_difference "AuditLog.where(action: 'standup.update', actor: users(:admin)).count", 1 do
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
      platform_channel: "temporary",
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

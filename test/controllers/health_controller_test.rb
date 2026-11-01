require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns basic health status" do
    get "/health"

    assert_response :success
    assert_equal "ok", JSON.parse(response.body)["status"]
  end

  test "returns detailed health checks" do
    get "/health/detailed"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("status")
    assert body["checks"].key?("database")
    assert body["checks"].key?("job_queue")
    assert body["checks"].key?("slack_api")
  end

  test "returns metrics" do
    get "/health/metrics"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("standups")
    assert body.key?("responses")
  end

  test "health host authorization exclusion is scoped to health endpoints" do
    exclusion = Rails.application.config.x.health_check_host_authorization_exclude
    request = Struct.new(:path)

    assert exclusion.call(request.new("/up"))
    assert exclusion.call(request.new("/health"))
    assert exclusion.call(request.new("/health/detailed"))
    refute exclusion.call(request.new("/healthcheck"))
    refute exclusion.call(request.new("/slack/events"))
  end
end

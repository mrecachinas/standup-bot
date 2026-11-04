require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns basic health status" do
    get "/health"

    assert_response :success
    assert_equal "ok", JSON.parse(response.body)["status"]
  end

  test "returns detailed health checks with the monitoring token" do
    with_health_check_token("monitor-token") do
      get "/health/detailed", headers: { "Authorization" => "Bearer monitor-token" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("status")
    assert body["checks"].key?("database")
    assert body["checks"].key?("job_queue")
    assert body["checks"].key?("slack_api")
  end

  test "returns metrics with the monitoring token" do
    with_health_check_token("monitor-token") do
      get "/health/metrics", headers: { "Authorization" => "Bearer monitor-token" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("standups")
    assert body.key?("responses")
  end

  test "detailed checks and metrics need the monitoring token" do
    with_health_check_token("monitor-token") do
      %w[/health/detailed /health/metrics].each do |path|
        get path
        assert_response :unauthorized, path

        get path, headers: { "Authorization" => "Bearer wrong-token" }
        assert_response :unauthorized, path
      end
    end
  end

  test "detailed checks and metrics are off without a monitoring token" do
    with_health_check_token(nil) do
      get "/health/metrics", headers: { "Authorization" => "Bearer " }
      assert_response :unauthorized
    end
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

  private

  def with_health_check_token(token)
    original = Rails.application.config.x.health_check_token
    Rails.application.config.x.health_check_token = token
    yield
  ensure
    Rails.application.config.x.health_check_token = original
  end
end

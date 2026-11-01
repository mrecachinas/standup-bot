require "test_helper"

class ApiRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = "test-admin-token"
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "throttles repeated sign-in attempts" do
    10.times do
      post api_session_path, params: { email: "nobody@example.com", access_token: "nope" }, as: :json
      assert_response :unauthorized
    end

    post api_session_path, params: { email: "nobody@example.com", access_token: "nope" }, as: :json
    assert_response :too_many_requests
  end

  test "bans an IP after repeated wrong admin tokens" do
    10.times do
      get api_standups_path, headers: { "Authorization" => "Bearer wrong" }, as: :json
      assert_response :unauthorized
    end

    get api_standups_path, headers: { "Authorization" => "Bearer test-admin-token" }, as: :json
    assert_response :forbidden
    assert_equal "blocked", response.parsed_body["error"]
  end
end

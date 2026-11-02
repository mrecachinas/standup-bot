require "test_helper"

class ApiRateLimitTest < ActionDispatch::IntegrationTest
  test "throttles repeated sign-in attempts from one IP" do
    10.times do |attempt|
      post api_session_path, params: { email: "nobody-#{attempt}@example.com", access_token: "nope" }, as: :json
      assert_response :unauthorized
    end

    post "/api/session.json", params: { email: "someone@example.com", access_token: "nope" }, as: :json
    assert_response :too_many_requests
  end

  test "throttles repeated sign-in attempts for one email" do
    5.times do
      post api_session_path, params: { email: "nobody@example.com", access_token: "nope" }, as: :json
      assert_response :unauthorized
    end

    post api_session_path, params: { email: " NOBODY@example.com", access_token: "nope" }, as: :json
    assert_response :too_many_requests
  end

  test "bans an IP after repeated wrong admin tokens" do
    10.times do
      get api_standups_path, headers: { "Authorization" => "Bearer wrong" }, as: :json
      assert_response :unauthorized
    end

    get api_standups_path, headers: token_headers, as: :json
    assert_response :forbidden
    assert_equal "blocked", response.parsed_body["error"]
  end
end

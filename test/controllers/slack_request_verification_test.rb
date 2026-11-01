require "test_helper"

class SlackRequestVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @signing_secret = Rails.application.config.slack[:signing_secret]
    @body = { type: "url_verification", challenge: "challenge_123" }.to_json
  end

  test "accepts a correctly signed Slack request" do
    timestamp = Time.now.to_i.to_s

    post events_url, params: @body, headers: slack_headers(timestamp, sign(timestamp))

    assert_response :success
    assert_equal "challenge_123", response.parsed_body["challenge"]
  end

  test "rejects an unsigned Slack request" do
    post events_url, params: @body, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "rejects a Slack request with a bad signature" do
    post events_url, params: @body, headers: slack_headers(Time.now.to_i.to_s, "v0=bad")

    assert_response :unauthorized
  end

  private

  def sign(timestamp)
    "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, "v0:#{timestamp}:#{@body}")
  end

  def slack_headers(timestamp, signature)
    {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => signature
    }
  end
end

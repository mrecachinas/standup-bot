require "test_helper"

class SlackSignatureVerifierTest < ActiveSupport::TestCase
  setup do
    @signing_secret = "test_signing_secret"
    @request_body = "request_body"
    @timestamp = Time.now.to_i.to_s

    Rails.application.config.slack ||= {}
    @original_signing_secret = Rails.application.config.slack[:signing_secret]
    Rails.application.config.slack[:signing_secret] = @signing_secret
  end

  teardown do
    Rails.application.config.slack[:signing_secret] = @original_signing_secret
  end

  test "accepts a validly signed request" do
    assert SlackSignatureVerifier.verify(slack_request(signature: sign(@timestamp)))
  end

  test "rejects an invalid signature" do
    refute SlackSignatureVerifier.verify(slack_request(signature: "v0=invalid_signature"))
  end

  test "rejects a signature computed over a different body" do
    request = slack_request(body: "tampered", signature: sign(@timestamp))

    refute SlackSignatureVerifier.verify(request)
  end

  test "rejects an expired timestamp" do
    old_timestamp = (Time.now - 6.minutes).to_i.to_s

    refute SlackSignatureVerifier.verify(slack_request(timestamp: old_timestamp, signature: sign(old_timestamp)))
  end

  test "rejects a non-numeric timestamp" do
    refute SlackSignatureVerifier.verify(slack_request(timestamp: "abc", signature: sign("abc")))
  end

  test "rejects when the signing secret is missing" do
    Rails.application.config.slack[:signing_secret] = nil

    refute SlackSignatureVerifier.verify(slack_request(signature: sign(@timestamp)))
  end

  test "rejects when the signing secret is blank" do
    Rails.application.config.slack[:signing_secret] = ""

    refute SlackSignatureVerifier.verify(slack_request(signature: sign(@timestamp)))
  end

  test "rejects missing headers" do
    refute SlackSignatureVerifier.verify(slack_request(timestamp: nil, signature: nil))
  end

  test "rejects a missing signature header" do
    refute SlackSignatureVerifier.verify(slack_request(signature: nil))
  end

  test "rejects a malformed signature" do
    refute SlackSignatureVerifier.verify(slack_request(signature: "invalid"))
  end

  private

  def sign(timestamp, body = @request_body)
    "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, "v0:#{timestamp}:#{body}")
  end

  def slack_request(signature:, timestamp: @timestamp, body: @request_body)
    headers = {
      "HTTP_X_SLACK_REQUEST_TIMESTAMP" => timestamp,
      "HTTP_X_SLACK_SIGNATURE" => signature
    }.compact
    ActionDispatch::Request.new(Rack::MockRequest.env_for("/slack/events", method: "POST", input: body, **headers))
  end
end

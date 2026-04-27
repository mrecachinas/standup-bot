require "test_helper"

class SlackSignatureVerifierTest < ActiveSupport::TestCase
  setup do
    @signing_secret = "test_signing_secret"
    @request_body = "request_body"
    @timestamp = Time.now.to_i.to_s

    # Mock the Rails config
    Rails.application.config.slack ||= {}
    Rails.application.config.slack[:signing_secret] = @signing_secret
  end

  test "should return true for valid signature" do
    # Create valid signature
    sig_basestring = "v0:#{@timestamp}:#{@request_body}"
    valid_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, sig_basestring)

    assert SlackSignatureVerifier.verify(@request_body, @timestamp, valid_signature)
  end

  test "should return false for invalid signature" do
    invalid_signature = "v0=invalid_signature"

    refute SlackSignatureVerifier.verify(@request_body, @timestamp, invalid_signature)
  end

  test "should return false for expired timestamp" do
    old_timestamp = (Time.now - 6.minutes).to_i.to_s
    sig_basestring = "v0:#{old_timestamp}:#{@request_body}"
    valid_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, sig_basestring)

    refute SlackSignatureVerifier.verify(@request_body, old_timestamp, valid_signature)
  end

  test "should return false when signing secret is missing" do
    Rails.application.config.slack[:signing_secret] = nil

    sig_basestring = "v0:#{@timestamp}:#{@request_body}"
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, sig_basestring)

    refute SlackSignatureVerifier.verify(@request_body, @timestamp, signature)
  end

  test "should return false for missing headers" do
    refute SlackSignatureVerifier.verify(@request_body, nil, nil)
  end

  test "should return false for malformed signature" do
    refute SlackSignatureVerifier.verify(@request_body, @timestamp, "invalid")
  end
end

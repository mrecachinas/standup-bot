require "openssl"

class SlackSignatureVerifier
  MAX_TIMESTAMP_AGE_SECONDS = 5.minutes.to_i
  SIGNATURE_VERSION = "v0="

  def self.verify(request_body, timestamp, signature)
    Rails.logger.info "Verifying Slack signature"

    signing_secret = slack_signing_secret
    if signing_secret.blank?
      Rails.logger.error "Slack signing secret is not configured"
      return false
    end

    if timestamp.blank? || signature.blank?
      Rails.logger.warn "Slack request rejected: missing signature headers"
      return false
    end

    request_time = Integer(timestamp, exception: false)
    unless request_time
      Rails.logger.warn "Slack request rejected: invalid timestamp"
      return false
    end

    unless signature.to_s.start_with?(SIGNATURE_VERSION)
      Rails.logger.warn "Slack request rejected: unsupported signature version"
      return false
    end

    # Verify the request is not more than 5 minutes old
    time_diff = (Time.now.to_i - request_time).abs
    if time_diff > MAX_TIMESTAMP_AGE_SECONDS
      Rails.logger.warn "Slack request rejected: timestamp too old (#{time_diff} seconds)"
      return false
    end

    # Compute the signature
    sig_basestring = "v0:#{timestamp}:#{request_body}"
    my_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

    # Compare the signatures
    result = signatures_match?(my_signature, signature.to_s)

    if result
      Rails.logger.info "Slack signature verification successful"
    else
      Rails.logger.warn "Slack signature verification failed"
    end

    result
  end

  def self.slack_signing_secret
    slack_config = Rails.application.config.slack || {}
    slack_config[:signing_secret] || slack_config["signing_secret"]
  end
  private_class_method :slack_signing_secret

  def self.signatures_match?(expected_signature, provided_signature)
    return false unless expected_signature.bytesize == provided_signature.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_signature, provided_signature)
  end
  private_class_method :signatures_match?
end

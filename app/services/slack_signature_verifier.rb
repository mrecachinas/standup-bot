require "openssl"

class SlackSignatureVerifier
  def self.verify(request_body, timestamp, signature)
    Rails.logger.info "Verifying Slack signature"
    Rails.logger.debug "Request timestamp: #{timestamp}, current time: #{Time.now.to_i}"

    # Verify the request is not more than 5 minutes old
    time_diff = (Time.now.to_i - timestamp.to_i).abs
    if time_diff > 300
      Rails.logger.warn "Slack request rejected: timestamp too old (#{time_diff} seconds)"
      return false
    end

    # Get your signing secret from config
    signing_secret = Rails.application.config.slack[:signing_secret]

    # Compute the signature
    sig_basestring = "v0:#{timestamp}:#{request_body}"
    my_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)
    Rails.logger.debug "Computed signature: #{my_signature[0..9]}..."

    # Compare the signatures
    result = ActiveSupport::SecurityUtils.secure_compare(my_signature, signature)

    if result
      Rails.logger.info "Slack signature verification successful"
    else
      Rails.logger.warn "Slack signature verification failed"
    end

    result
  end
end

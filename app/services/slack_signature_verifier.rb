class SlackSignatureVerifier
  MAX_TIMESTAMP_AGE_SECONDS = 5.minutes.to_i

  def self.verify(request)
    signing_secret = slack_signing_secret
    if signing_secret.blank?
      Rails.logger.error "Slack signing secret is not configured"
      return false
    end

    Slack::Events::Request.new(
      request,
      signing_secret: signing_secret,
      signature_expires_in: MAX_TIMESTAMP_AGE_SECONDS
    ).verify!
  rescue Slack::Events::Request::TimestampExpired, Slack::Events::Request::InvalidSignature => e
    Rails.logger.warn "Slack request rejected: #{e.class.name.demodulize}"
    false
  end

  def self.slack_signing_secret
    slack_config = Rails.application.config.slack || {}
    slack_config[:signing_secret] || slack_config["signing_secret"]
  end
  private_class_method :slack_signing_secret
end

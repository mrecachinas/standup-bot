class ApplicationController < ActionController::API
  private

  def verify_slack_request
    timestamp = request.headers["X-Slack-Request-Timestamp"]
    signature = request.headers["X-Slack-Signature"]

    request.body.rewind
    body = request.body.read
    request.body.rewind

    unless SlackSignatureVerifier.verify(body, timestamp, signature)
      head :unauthorized
      return false
    end

    true
  end
end

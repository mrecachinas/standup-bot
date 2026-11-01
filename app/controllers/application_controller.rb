class ApplicationController < ActionController::API
  private

  def verify_slack_request
    return true if SlackSignatureVerifier.verify(request)

    head :unauthorized
    false
  end
end

class HealthController < ApplicationController
  # The detailed checks and metrics show how the installation is set up and
  # used, so they need the HEALTH_CHECK_TOKEN. /up and /health stay open for
  # load balancers.
  before_action :authenticate_monitoring!, only: %i[detailed metrics]

  def show
    render json: { status: "ok", timestamp: Time.current.iso8601 }
  end

  def detailed
    payload = HealthCheckService.call
    status = payload[:status] == "unhealthy" ? :service_unavailable : :ok
    render json: payload, status: status
  end

  def metrics
    render json: HealthCheckService.metrics
  end

  private

  def authenticate_monitoring!
    expected = Rails.application.config.x.health_check_token
    provided = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    return if expected.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end

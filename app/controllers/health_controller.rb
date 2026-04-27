class HealthController < ApplicationController
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
end

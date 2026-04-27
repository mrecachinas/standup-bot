module Api
  class BaseController < ApplicationController
    before_action :authenticate_admin!

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActionController::ParameterMissing, with: :render_bad_request

    private

    def authenticate_admin!
      token = configured_admin_token

      unless token.present?
        render json: { error: "Admin API token is not configured" }, status: :service_unavailable
        return
      end

      provided_token = request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
      unless secure_token_match?(provided_token, token)
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    def configured_admin_token
      ENV["ADMIN_API_TOKEN"].presence ||
        Rails.application.credentials.dig(:admin, :api_token).presence ||
        Rails.application.credentials.dig(:admin_api_token).presence
    end

    def secure_token_match?(provided_token, configured_token)
      provided_token.bytesize == configured_token.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided_token, configured_token)
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end

    def audit_admin_change!(action, auditable:, metadata: {})
      AuditLogger.log!(
        actor: nil,
        actor_label: "admin_api",
        action: action,
        auditable: auditable,
        metadata: metadata.merge(auth_method: "admin_api_token"),
        request: request
      )
    end
  end
end

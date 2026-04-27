module Web
  class ApplicationController < ActionController::Base
    layout "web"

    helper_method :current_user

    private

    def current_user
      @current_user ||= User.active.find_by(id: session[:user_id]) if session[:user_id].present?
    end

    def authenticate_user!
      return if current_user

      respond_to do |format|
        format.html { redirect_to new_session_path, status: :see_other }
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
        format.any { head :unauthorized }
      end
    end

    def authorize_standup!(standup)
      return if standup.manageable_by?(current_user)

      respond_to do |format|
        format.html { render plain: "Forbidden", status: :forbidden }
        format.json { render json: { error: "Forbidden" }, status: :forbidden }
        format.any { head :forbidden }
      end
    end

    def manageable_standups
      Standup.manageable_by(current_user)
    end

    def audit_manager_change!(action, auditable:, metadata: {})
      AuditLogger.log!(actor: current_user, action: action, auditable: auditable, metadata: metadata, request: request)
    end
  end
end

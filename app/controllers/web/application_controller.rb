module Web
  class ApplicationController < ActionController::Base
    AuthorizationNotPerformed = Class.new(StandardError)

    layout "web"

    helper_method :current_user, :current_member, :sidebar_standups

    # Every action must call authorize_standup!, require_admin!, or
    # skip_authorization, so a new action can't silently skip the ownership check.
    after_action :verify_authorized

    private

    def current_user
      @current_user ||= User.active.find_by(id: session[:user_id]) if session[:user_id].present?
    end

    def current_member
      return @current_member if defined?(@current_member)

      @current_member = Member.for(session[:slack_id], name: session[:slack_name])
    end

    def sidebar_standups
      return [] unless current_user

      @sidebar_standups ||= manageable_standups.order(:name).select(:id, :name, :active).to_a
    end

    def authenticate_user!
      return if current_user

      respond_to do |format|
        format.html { redirect_to(current_member ? me_root_path : new_session_path, status: :see_other) }
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
        format.any { head :unauthorized }
      end
    end

    def authorize_standup!(standup)
      @authorization_checked = true
      return if standup.manageable_by?(current_user)

      respond_to do |format|
        format.html { render plain: "Forbidden", status: :forbidden }
        format.json { render json: { error: "Forbidden" }, status: :forbidden }
        format.any { head :forbidden }
      end
    end

    def require_admin!
      @authorization_checked = true
      return if current_user&.admin?

      render plain: "Forbidden", status: :forbidden
    end

    # For actions any signed-in user may take, such as creating a standup or
    # listing their own (already scoped by manageable_standups).
    def skip_authorization
      @authorization_checked = true
    end

    def verify_authorized
      return if @authorization_checked

      raise AuthorizationNotPerformed, "#{self.class.name}##{action_name} didn't check authorization"
    end

    def manageable_standups
      Standup.manageable_by(current_user)
    end

    def audit_manager_change!(action, auditable:, metadata: {})
      AuditLogger.log!(actor: current_user, action: action, auditable: auditable, metadata: metadata, request: request)
    end
  end
end

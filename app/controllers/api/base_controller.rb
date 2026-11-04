module Api
  # Every request acts as a user, who arrives one of two ways:
  #
  # * Scripts send that user's access token as "Authorization: Bearer <token>".
  #   The session cookie is never read, and CSRF doesn't apply.
  # * The console sends its session cookie and an X-CSRF-Token header.
  #
  # Either way the user only sees what they may manage (admins see everything).
  # A request with an Authorization header is always a token request; a wrong
  # token is rejected outright and never falls back to the cookie.
  class BaseController < ActionController::Base
    AuthorizationNotPerformed = Class.new(StandardError)

    protect_from_forgery with: :exception, unless: :token_request?

    rescue_from ActionController::InvalidAuthenticityToken, with: :render_invalid_authenticity_token
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActionController::ParameterMissing, with: :render_bad_request
    rescue_from ActionController::BadRequest, with: :render_bad_request

    before_action :resolve_principal
    before_action :set_instrumentation_context
    before_action :authenticate!

    # Every action must call authorize_standup!, require_admin!, require_member!,
    # or skip_authorization, so a new action can't silently skip the check.
    after_action :verify_authorized

    private

    attr_reader :principal

    def token_request?
      request.headers.key?("HTTP_AUTHORIZATION")
    end

    def resolve_principal
      @principal =
        if token_request?
          principal_from_token
        else
          Principal.from_session(user: current_user, member: current_member)
        end
    end

    def principal_from_token
      user = User.authenticate_bearer(request.authorization.to_s[/\ABearer (.+)\z/, 1])
      unless user
        render_unauthorized
        return
      end

      @current_user = user
      Principal.from_bearer(user)
    end

    # Ties log lines and error reports to who made the request.
    def set_instrumentation_context
      Instrumentation.set_context(user_id: @current_user&.id, member: member_label)
    end

    # Adds the same to the request's log line (see config/initializers/lograge.rb).
    def append_info_to_payload(payload)
      super
      payload[:user_id] = @current_user&.id
      payload[:member] = member_label
    end

    def member_label
      member = @current_member if defined?(@current_member)
      "#{member.platform}:#{member.platform_user_id}" if member
    end

    def authenticate!
      render_unauthorized unless principal&.authenticated?
    end

    # The bearer token's user, or the signed-in user from the session.
    def current_user
      return @current_user if token_request?

      @current_user ||= User.active.find_by(id: session[:user_id]) if session[:user_id].present?
    end

    def current_member
      return if token_request?
      return @current_member if defined?(@current_member)

      @current_member = Member.for(session[:member_platform], session[:member_user_id], name: session[:member_name])
    end

    # The management side of the console: anyone with an account.
    def require_manager!
      return if principal.manager?

      render_forbidden("Sign in with an account to manage standups.")
    end

    def require_session!
      render_forbidden("This endpoint needs a console session.") if token_request?
    end

    # Member endpoints only read the signed-in member's own data.
    def require_member!
      @authorization_checked = true
      return if current_member

      if token_request?
        render_forbidden("Member endpoints need a console session.")
      else
        render_forbidden("Sign in with Slack or Microsoft to see your own standups.")
      end
    end

    def authorize_standup!(standup)
      @authorization_checked = true
      return true if principal.can_manage?(standup)

      render_forbidden
      false
    end

    def require_admin!
      @authorization_checked = true
      render_forbidden unless principal.admin?
    end

    # For actions any signed-in manager may take, such as creating a standup
    # or listing their own (already scoped by manageable_standups).
    def skip_authorization
      @authorization_checked = true
    end

    def verify_authorized
      return if @authorization_checked

      raise AuthorizationNotPerformed, "#{self.class.name}##{action_name} didn't check authorization"
    end

    def manageable_standups
      principal.manageable_standups
    end

    def set_standup
      @standup = Standup.find(params[:standup_id] || params[:id])
      authorize_standup!(@standup)
    end

    def audit_change!(action, auditable:, metadata: {})
      AuditLogger.log!(
        **principal.audit_attributes,
        action: action,
        auditable: auditable,
        metadata: metadata.merge(principal.audit_metadata),
        request: request
      )
    end

    def period_days
      params.fetch(:period_days, 30).to_i.clamp(1, 365)
    end

    # `errors` keeps the full-message array the admin API has always returned;
    # `field_errors` maps attributes to messages for form validation.
    def render_validation_errors(errors, status: :unprocessable_entity)
      render json: {
        errors: errors.full_messages,
        field_errors: errors.to_hash(false).transform_keys(&:to_s)
      }, status: status
    end

    def render_unauthorized
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def render_forbidden(message = "Forbidden")
      render json: { error: message }, status: :forbidden
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end

    def render_invalid_authenticity_token
      render json: { error: "Invalid authenticity token" }, status: :unprocessable_entity
    end
  end
end

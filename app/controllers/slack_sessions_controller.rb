class SlackSessionsController < Web::ApplicationController
  STATE_SESSION_KEY = :slack_sign_in_state

  def new
    unless SlackSignIn.configured?
      redirect_to new_session_path, alert: "Sign in with Slack isn't set up yet. Use an access token instead.", status: :see_other
      return
    end

    state = SecureRandom.urlsafe_base64(32)
    session[STATE_SESSION_KEY] = state
    redirect_to SlackSignIn.authorize_url(redirect_uri: slack_sign_in_callback_url, state: state), allow_other_host: true, status: :see_other
  end

  def callback
    expected_state = session.delete(STATE_SESSION_KEY)
    return fail_sign_in("Slack sign-in was cancelled.") if params[:error].present?
    return fail_sign_in("Your sign-in link expired. Please try again.") unless valid_state?(expected_state)

    identity = SlackSignIn.new.identity_for(code: params[:code], redirect_uri: slack_sign_in_callback_url)
    user = linked_user_for(identity)
    member = Member.for(identity.slack_id, name: identity.name)
    return fail_sign_in("You're not part of any standups yet. Ask your manager to add you.") unless user || member

    reset_session
    session[:slack_id] = identity.slack_id
    session[:slack_name] = identity.name
    if user
      session[:user_id] = user.id
      user.update!(last_signed_in_at: Time.current)
    end

    redirect_to(user ? manager_standups_path : me_root_path, status: :see_other)
  rescue SlackSignIn::Error => error
    fail_sign_in(error.message)
  end

  private

  def valid_state?(expected_state)
    expected_state.present? && params[:state].present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
  end

  def linked_user_for(identity)
    return unless identity.email.present? && identity.email_verified

    User.active.find_by(email: User.normalize_email(identity.email))
  end

  def fail_sign_in(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end
end

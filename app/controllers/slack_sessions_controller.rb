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
    user = User.from_slack_identity(identity)
    return fail_sign_in("Your account has been turned off. Ask an admin to turn it back on.") unless user.active?

    reset_session
    session[:user_id] = user.id
    session[:slack_id] = identity.slack_id
    session[:slack_name] = identity.name
    user.update!(last_signed_in_at: Time.current)

    redirect_to landing_path_for(user, identity), status: :see_other
  rescue SlackSignIn::Error, User::LinkConflict, ActiveRecord::RecordInvalid => error
    fail_sign_in(error.message)
  end

  private

  def valid_state?(expected_state)
    expected_state.present? && params[:state].present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
  end

  # People who only take part in standups land on their own check-ins;
  # anyone who runs a standup (or has none yet) lands on the console.
  def landing_path_for(user, identity)
    return manager_standups_path if user.admin? || user.standup_ownerships.exists?

    Member.for(identity.slack_id) ? me_root_path : manager_standups_path
  end

  def fail_sign_in(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end
end

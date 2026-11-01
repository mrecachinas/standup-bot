class SlackSessionsController < ActionController::Base
  include PlatformSignIn

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
    complete_sign_in(:slack, identity)
  rescue SlackSignIn::Error, User::LinkConflict, ActiveRecord::RecordInvalid => error
    fail_sign_in(error.message)
  end
end

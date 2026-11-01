class MicrosoftSessionsController < ActionController::Base
  include PlatformSignIn

  STATE_SESSION_KEY = :microsoft_sign_in_state
  NONCE_SESSION_KEY = :microsoft_sign_in_nonce

  def new
    unless MicrosoftSignIn.configured?
      redirect_to new_session_path, alert: "Sign in with Microsoft isn't set up yet. Use an access token instead.", status: :see_other
      return
    end

    state = SecureRandom.urlsafe_base64(32)
    nonce = SecureRandom.urlsafe_base64(32)
    session[STATE_SESSION_KEY] = state
    session[NONCE_SESSION_KEY] = nonce
    redirect_to MicrosoftSignIn.authorize_url(redirect_uri: microsoft_sign_in_callback_url, state: state, nonce: nonce),
      allow_other_host: true, status: :see_other
  end

  def callback
    expected_state = session.delete(STATE_SESSION_KEY)
    nonce = session.delete(NONCE_SESSION_KEY)
    return fail_sign_in("Microsoft sign-in was cancelled.") if params[:error].present?
    return fail_sign_in("Your sign-in link expired. Please try again.") unless valid_state?(expected_state)

    identity = MicrosoftSignIn.new.identity_for(code: params[:code], redirect_uri: microsoft_sign_in_callback_url, nonce: nonce)
    complete_sign_in(:teams, identity)
  rescue MicrosoftSignIn::Error, User::LinkConflict, ActiveRecord::RecordInvalid => error
    fail_sign_in(error.message)
  end
end

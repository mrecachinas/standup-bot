# Shared by the "Sign in with <platform>" controllers: finish signing someone
# in once their platform identity has been verified.
module PlatformSignIn
  extend ActiveSupport::Concern

  private

  def complete_sign_in(platform, identity)
    user = User.from_identity(platform, identity)
    return fail_sign_in("Your account has been turned off. Ask an admin to turn it back on.") unless user.active?

    reset_session
    session[:user_id] = user.id
    session[:member_platform] = platform.to_s
    session[:member_user_id] = identity.user_id
    session[:member_name] = identity.name
    user.update!(last_signed_in_at: Time.current)
    refresh_avatar(platform, user, identity)

    redirect_to landing_path_for(platform, user, identity), status: :see_other
  end

  def valid_state?(expected_state)
    expected_state.present? && params[:state].present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
  end

  # People who only take part in standups land on their own check-ins;
  # anyone who runs a standup (or has none yet) lands on the console.
  def landing_path_for(platform, user, identity)
    return manager_standups_path if user.admin? || user.standup_ownerships.exists?

    Member.for(platform, identity.user_id) ? me_root_path : manager_standups_path
  end

  # Sign-in is a free chance to pick up a changed photo everywhere it's shown.
  def refresh_avatar(platform, user, identity)
    return unless AvatarUrl.safe?(identity.avatar_url)

    user.update_columns(avatar_url: identity.avatar_url) if user.avatar_url != identity.avatar_url
    StandupParticipant.on_platform(platform).where(platform_user_id: identity.user_id).update_all(avatar_url: identity.avatar_url)
  end

  def fail_sign_in(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end
end

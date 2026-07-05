class SessionsController < Web::ApplicationController
  def new
    if current_user
      redirect_to manager_standups_path, status: :see_other
    else
      prepare_local_development_prefill
    end
  end

  def create
    user = User.authenticate(params[:email], params[:access_token])

    if user
      reset_session
      session[:user_id] = user.id
      user.update!(last_signed_in_at: Time.current)
      redirect_to manager_standups_path, status: :see_other
    else
      @email = params[:email]
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def prepare_local_development_prefill
    return unless Rails.env.development?

    @email = ENV["MANAGER_ADMIN_EMAIL"].presence
    @access_token = ENV["MANAGER_ADMIN_TOKEN"].presence
  end
end

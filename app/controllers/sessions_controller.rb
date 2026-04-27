class SessionsController < Web::ApplicationController
  def new
    redirect_to manager_standups_path, status: :see_other if current_user
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
end

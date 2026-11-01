module Me
  class ApplicationController < Web::ApplicationController
    before_action :authenticate_member!

    private

    def authenticate_member!
      return if current_member

      if current_user
        redirect_to manager_standups_path, alert: "Sign in with Slack to see your own standups.", status: :see_other
      else
        redirect_to new_session_path, status: :see_other
      end
    end
  end
end

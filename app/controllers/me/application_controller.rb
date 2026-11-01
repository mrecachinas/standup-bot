module Me
  class ApplicationController < Web::ApplicationController
    # Member pages only read the signed-in member's own standups via current_member.
    skip_after_action :verify_authorized
    before_action :authenticate_member!

    private

    def authenticate_member!
      return if current_member

      if current_user
        redirect_to manager_standups_path, alert: "Sign in with Slack or Microsoft to see your own standups.", status: :see_other
      else
        redirect_to new_session_path, status: :see_other
      end
    end
  end
end

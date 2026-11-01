# Lets the end-to-end tests (script/e2e-server) sign in "with Slack" without
# Slack. The browser test intercepts the redirect to slack.com and returns to
# the real callback with a Slack user ID as the code; everything after that
# (state check, account linking, the member session) runs as usual.
if ENV["E2E_FAKE_SLACK_SIGN_IN"] == "1"
  raise "E2E_FAKE_SLACK_SIGN_IN must never be set in production" if Rails.env.production?

  Rails.application.config.to_prepare do
    SlackSignIn.prepend(Module.new do
      def identity_for(code:, redirect_uri:)
        participant = StandupParticipant.on_platform(:slack).find_by(platform_user_id: code)
        User::Identity.new(user_id: code, team_id: self.class.config_value(:team_id), email: nil, email_verified: false,
          name: participant&.display_name || code)
      end
    end)
  end
end

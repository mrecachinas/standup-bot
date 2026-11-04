# "Sign in with Slack" via Slack's OpenID Connect endpoints.
class SlackSignIn
  AUTHORIZE_URL = "https://slack.com/openid/connect/authorize".freeze
  SCOPES = %w[openid email profile].freeze

  Error = Class.new(StandardError)

  def self.configured?
    config_value(:client_id).present? && config_value(:client_secret).present?
  end

  def self.authorize_url(redirect_uri:, state:)
    params = {
      response_type: "code",
      scope: SCOPES.join(" "),
      client_id: config_value(:client_id),
      redirect_uri: redirect_uri,
      state: state
    }
    params[:team] = config_value(:team_id) if config_value(:team_id).present?
    "#{AUTHORIZE_URL}?#{params.to_query}"
  end

  def self.config_value(key)
    config = Rails.application.config.slack || {}
    value = config.respond_to?(:[]) ? (config[key] || config[key.to_s]) : nil
    value.presence
  end

  def identity_for(code:, redirect_uri:)
    raise Error, "Slack sign-in isn't configured." unless self.class.configured?
    raise Error, "Slack didn't return an authorization code." if code.blank?

    token = Slack::Web::Client.new.openid_connect_token(
      client_id: self.class.config_value(:client_id),
      client_secret: self.class.config_value(:client_secret),
      code: code,
      redirect_uri: redirect_uri
    )
    info = Slack::Web::Client.new(token: token["access_token"]).openid_connect_userInfo
    identity = build_identity(info)
    verify_team!(identity)
    verify_full_member!(identity)
    identity
  rescue Slack::Web::Api::Errors::SlackError, Faraday::Error => error
    Rails.error.report(error, source: "slack_sign_in")
    raise Error, "Slack sign-in failed. Please try again."
  end

  private

  def build_identity(info)
    slack_id = info["https://slack.com/user_id"].presence || info["sub"].presence
    raise Error, "Slack didn't return a user ID." if slack_id.blank?

    User::Identity.new(
      user_id: slack_id,
      team_id: info["https://slack.com/team_id"],
      email: info["email"],
      email_verified: ActiveModel::Type::Boolean.new.cast(info["email_verified"]),
      name: info["name"].presence || info["given_name"].presence || slack_id,
      avatar_url: [ info["https://slack.com/user_image_72"], info["picture"] ].find { |url| AvatarUrl.safe?(url) }
    )
  end

  # Always pin sign-in to one workspace. Otherwise an owner of some other
  # workspace could set a member's email to a manager's address and sign in as them.
  def verify_team!(identity)
    expected_team = self.class.config_value(:team_id) || bot_team_id
    raise Error, "Slack sign-in needs SLACK_TEAM_ID or a working bot token." if expected_team.blank?
    return if identity.team_id == expected_team

    raise Error, "That Slack workspace isn't connected to Standup Bot."
  end

  # Guests can't sign in: anyone who can sign in can create standups and use
  # the bot's workspace lookups. Fail closed if Slack can't confirm the account.
  def verify_full_member!(identity)
    profile = ChatPlatform.for(:slack).user_profile(identity.user_id)
    raise Error, "Slack sign-in couldn't confirm your account. Please try again." if profile.nil?
    raise Error, "Guest accounts can't sign in to Standup Bot." if profile.guest?
    raise Error, "That Slack account can't sign in to Standup Bot." if profile.deleted? || profile.bot?
  end

  def bot_team_id
    Rails.cache.fetch("slack_sign_in/bot_team_id", expires_in: 1.hour, skip_nil: true) do
      ChatPlatform.for(:slack).connection_status&.dig("team_id").presence
    end
  rescue StandardError => error
    Rails.logger.warn("Could not look up the bot's Slack workspace: #{error.class}")
    nil
  end
end

# "Sign in with Microsoft" via Entra ID OpenID Connect, pinned to the Teams
# tenant. People sign in as their Entra object ID, the same ID the Teams
# adapter uses for participants.
class MicrosoftSignIn
  SCOPES = %w[openid profile email].freeze
  LOGIN_HOST = "https://login.microsoftonline.com".freeze

  Error = Class.new(StandardError)

  def self.configured?
    Microsoft::Config.tenant_id.present? && Microsoft::Config.sign_in_client_id.present? && Microsoft::Config.sign_in_client_secret.present?
  end

  def self.authorize_url(redirect_uri:, state:, nonce:)
    params = {
      client_id: Microsoft::Config.sign_in_client_id,
      response_type: "code",
      response_mode: "query",
      redirect_uri: redirect_uri,
      scope: SCOPES.join(" "),
      state: state,
      nonce: nonce,
      prompt: "select_account"
    }
    "#{LOGIN_HOST}/#{ERB::Util.url_encode(Microsoft::Config.tenant_id)}/oauth2/v2.0/authorize?#{params.to_query}"
  end

  def initialize(connection: nil, verifier: nil)
    @connection = connection
    @verifier = verifier
  end

  def identity_for(code:, redirect_uri:, nonce:)
    raise Error, "Microsoft sign-in isn't configured." unless self.class.configured?
    raise Error, "Microsoft didn't return an authorization code." if code.blank?

    claims = verifier.verify!(exchange_code(code, redirect_uri), nonce: nonce)
    identity = build_identity(claims)
    verify_full_member!(identity)
    identity
  rescue Microsoft::IdTokenVerifier::Invalid => error
    raise Error, error.message
  rescue Microsoft::ApiError, Faraday::Error => error
    Rails.logger.warn("Microsoft sign-in failed: #{error.class}: #{error.message}")
    raise Error, "Microsoft sign-in failed. Please try again."
  end

  private

  def exchange_code(code, redirect_uri)
    response = connection.post(
      "/#{ERB::Util.url_encode(Microsoft::Config.tenant_id)}/oauth2/v2.0/token",
      URI.encode_www_form(
        grant_type: "authorization_code",
        client_id: Microsoft::Config.sign_in_client_id,
        client_secret: Microsoft::Config.sign_in_client_secret,
        code: code,
        redirect_uri: redirect_uri,
        scope: SCOPES.join(" ")
      ),
      "Content-Type" => "application/x-www-form-urlencoded"
    )
    body = JSON.parse(response.body.presence || "{}")
    raise Error, "Microsoft sign-in failed. Please try again." unless response.success? && body["id_token"].present?

    body["id_token"]
  rescue JSON::ParserError
    raise Error, "Microsoft sign-in failed. Please try again."
  end

  # Entra's email claim isn't verified by default, so it's only used to link an
  # existing account when the tenant sends xms_edov (email domain owner verified).
  def build_identity(claims)
    object_id = claims["oid"].to_s.downcase
    raise Error, "Microsoft didn't return a user ID." if object_id.blank?

    User::Identity.new(
      user_id: object_id,
      team_id: claims["tid"],
      email: claims["email"].presence || claims["preferred_username"],
      email_verified: ActiveModel::Type::Boolean.new.cast(claims["xms_edov"]) == true && claims["email"].present?,
      name: claims["name"].presence || claims["preferred_username"].presence || object_id,
      avatar_url: nil
    )
  end

  # Guests can't sign in, same as with Slack. Fail closed if Graph can't confirm.
  def verify_full_member!(identity)
    profile = ChatPlatform.for(:teams).user_profile(identity.user_id)
    raise Error, "Microsoft sign-in couldn't confirm your account. Please try again." if profile.nil?
    raise Error, "Guest accounts can't sign in to Standup Bot." if profile.guest?
    raise Error, "That Microsoft account can't sign in to Standup Bot." if profile.deleted?
  end

  def verifier
    @verifier ||= Microsoft::IdTokenVerifier.new
  end

  def connection
    @connection ||= Faraday.new(url: LOGIN_HOST, request: { timeout: 10, open_timeout: 5 })
  end
end

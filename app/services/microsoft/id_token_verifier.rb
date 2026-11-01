module Microsoft
  # Validates an Entra ID (v2.0) ID token from "Sign in with Microsoft",
  # pinned to the configured tenant.
  class IdTokenVerifier
    CLOCK_SKEW = 5.minutes.to_i

    Invalid = Class.new(StandardError)

    def initialize(tenant_id: Config.tenant_id, client_id: Config.sign_in_client_id, keys: nil)
      @tenant_id = tenant_id
      @client_id = client_id
      @keys = keys || OpenIdKeys.new(metadata_url: "https://login.microsoftonline.com/#{ERB::Util.url_encode(tenant_id)}/v2.0/.well-known/openid-configuration")
    end

    def verify!(id_token, nonce:)
      payload, = JWT.decode(
        id_token, nil, true,
        algorithms: [ "RS256" ],
        jwks: keys.loader,
        iss: "https://login.microsoftonline.com/#{tenant_id}/v2.0", verify_iss: true,
        aud: client_id, verify_aud: true,
        leeway: CLOCK_SKEW
      )

      raise Invalid, "That Microsoft account belongs to a different organization." unless payload["tid"] == tenant_id
      raise Invalid, "Sign-in response didn't match this request." unless nonce.present? && ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, nonce.to_s)

      payload
    rescue JWT::DecodeError, ApiError => error
      raise Invalid, "Couldn't verify the Microsoft sign-in (#{error.class.name.demodulize})."
    end

    private

    attr_reader :tenant_id, :client_id, :keys
  end
end

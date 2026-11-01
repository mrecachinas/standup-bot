module Microsoft
  # Verifies the JWT the Bot Connector sends with every Teams activity, per
  # https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication
  class BotFrameworkAuth
    ISSUER = "https://api.botframework.com".freeze
    METADATA_URL = "https://login.botframework.com/v1/.well-known/openidconfiguration".freeze
    CLOCK_SKEW = 5.minutes.to_i

    Unauthorized = Class.new(StandardError)

    def self.keys
      @keys ||= OpenIdKeys.new(metadata_url: METADATA_URL)
    end

    def initialize(keys: self.class.keys, app_id: Config.app_id)
      @keys = keys
      @app_id = app_id
    end

    def verify!(authorization_header, service_url:, channel_id:)
      raise Unauthorized, "Teams isn't configured" if app_id.blank?

      token = authorization_header.to_s[/\ABearer (\S+)\z/, 1]
      raise Unauthorized, "Missing bearer token" if token.blank?

      payload, header = JWT.decode(
        token, nil, true,
        algorithms: [ "RS256" ],
        jwks: keys.loader,
        iss: ISSUER, verify_iss: true,
        aud: app_id, verify_aud: true,
        leeway: CLOCK_SKEW
      )

      # The Bot Connector names this claim "serviceurl"; JWT claim names are case-sensitive.
      claimed_service_url = payload["serviceurl"] || payload["serviceUrl"]
      raise Unauthorized, "serviceurl claim doesn't match the activity" unless same_url?(claimed_service_url, service_url)
      raise Unauthorized, "Signing key isn't endorsed for #{channel_id}" unless endorsed?(header["kid"], channel_id)

      payload
    rescue JWT::DecodeError, ApiError => error
      raise Unauthorized, error.message
    end

    private

    attr_reader :keys, :app_id

    def same_url?(claim, service_url)
      claim.present? && service_url.present? && claim.to_s.chomp("/").casecmp?(service_url.to_s.chomp("/"))
    end

    def endorsed?(kid, channel_id)
      endorsements = keys.key(kid)&.fetch("endorsements", nil)
      endorsements.nil? || endorsements.include?(channel_id.to_s)
    end
  end
end

module Microsoft
  # Signing keys from an OpenID metadata document, cached and refreshed when a
  # token uses a key we haven't seen (Microsoft rotates them).
  class OpenIdKeys
    CACHE_TTL = 12.hours

    def initialize(metadata_url:, connection: nil)
      @metadata_url = metadata_url
      @connection = connection
    end

    # For JWT.decode(..., jwks: keys.loader).
    def loader
      ->(options) { JWT::JWK::Set.new(document(force: options[:kid_not_found] || options[:invalidate])) }
    end

    def key(kid)
      Array(document["keys"]).find { |key| key["kid"] == kid }
    end

    def document(force: false)
      Rails.cache.delete(cache_key) if force
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_keys }
    end

    private

    attr_reader :metadata_url

    def cache_key
      "microsoft/openid_keys/#{Digest::SHA256.hexdigest(metadata_url)}"
    end

    def fetch_keys
      metadata = get_json(metadata_url)
      jwks_uri = metadata["jwks_uri"]
      raise ApiError, "OpenID metadata at #{metadata_url} has no jwks_uri" unless jwks_uri.to_s.start_with?("https://")

      keys = get_json(jwks_uri)
      raise ApiError, "No signing keys at #{jwks_uri}" if Array(keys["keys"]).empty?

      keys
    end

    def get_json(url)
      response = connection.get(url)
      raise ApiError.new("Couldn't load #{url} (#{response.status})", status: response.status) unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError => error
      raise ApiError, "Couldn't load #{url}: #{error.class}"
    end

    def connection
      @connection ||= Faraday.new(request: { timeout: 10, open_timeout: 5 })
    end
  end
end

module Microsoft
  # Client-credentials tokens for the Bot Connector and Microsoft Graph,
  # cached in memory until shortly before they expire.
  class TokenProvider
    BOT_CONNECTOR_SCOPE = "https://api.botframework.com/.default".freeze
    GRAPH_SCOPE = "https://graph.microsoft.com/.default".freeze
    LOGIN_HOST = "https://login.microsoftonline.com".freeze
    EXPIRY_MARGIN = 5.minutes

    class << self
      def instance
        @instance ||= new
      end

      def reset!
        @instance = nil
      end
    end

    def initialize(connection: nil)
      @connection = connection
      @tokens = {}
      @mutex = Mutex.new
    end

    def token(scope)
      @mutex.synchronize do
        cached = @tokens[scope]
        return cached[:value] if cached && cached[:expires_at] > EXPIRY_MARGIN.from_now

        @tokens[scope] = fetch(scope)
        @tokens[scope][:value]
      end
    end

    def invalidate(scope)
      @mutex.synchronize { @tokens.delete(scope) }
    end

    private

    def fetch(scope)
      raise ApiError, "Microsoft Teams isn't configured (TEAMS_APP_ID, TEAMS_APP_PASSWORD, TEAMS_TENANT_ID)." unless Config.bot_configured?

      response = connection.post(
        "/#{ERB::Util.url_encode(Config.tenant_id)}/oauth2/v2.0/token",
        URI.encode_www_form(
          grant_type: "client_credentials",
          client_id: Config.app_id,
          client_secret: Config.app_password,
          scope: scope
        ),
        "Content-Type" => "application/x-www-form-urlencoded"
      )
      body = JSON.parse(response.body.presence || "{}")

      unless response.success? && body["access_token"].present?
        raise ApiError.new("Microsoft login rejected the app credentials (#{body['error'] || response.status}).", status: response.status, code: body["error"])
      end

      { value: body["access_token"], expires_at: body["expires_in"].to_i.seconds.from_now }
    rescue Faraday::Error, JSON::ParserError => error
      raise ApiError, "Couldn't reach Microsoft login: #{error.class}"
    end

    def connection
      @connection ||= Faraday.new(url: LOGIN_HOST, request: { timeout: 10, open_timeout: 5 })
    end
  end
end

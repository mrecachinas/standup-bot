module Microsoft
  # The Bot Framework Connector REST API, which Teams bots use to start
  # conversations and send, and edit, messages.
  class BotConnectorClient
    # Only send the bot token to Microsoft's own service URLs, even if a bad
    # value ends up in the database.
    # Exact Bot Connector hosts: trafficmanager.net subdomains are self-service
    # Azure profiles, so a suffix match would trust anyone's.
    TRUSTED_SERVICE_HOSTS = %w[
      smba.trafficmanager.net
      smba.infra.gcc.teams.microsoft.com
      smba.infra.gov.teams.microsoft.us
      smba.infra.dod.teams.microsoft.us
    ].freeze
    TRUSTED_SERVICE_HOST_SUFFIX = /\.botframework\.(com|azure\.us)\z/

    UntrustedServiceUrl = Class.new(ApiError)

    def initialize(http: HttpClient.new(scope: TokenProvider::BOT_CONNECTOR_SCOPE))
      @http = http
    end

    def self.trusted_service_url?(service_url)
      uri = URI.parse(service_url.to_s)
      host = uri.host.to_s.downcase
      uri.is_a?(URI::HTTPS) && (TRUSTED_SERVICE_HOSTS.include?(host) || host.match?(TRUSTED_SERVICE_HOST_SUFFIX))
    rescue URI::InvalidURIError
      false
    end

    # Opens (or reuses) the bot's 1:1 chat with a user by Entra object ID.
    # Teams returns 403 if the app isn't installed for that user.
    def create_personal_conversation(service_url:, user_id:, tenant_id:)
      response = http.post(
        url(service_url, "v3/conversations"),
        {
          bot: { id: "28:#{Config.app_id}" },
          members: [ { id: user_id } ],
          channelData: { tenant: { id: tenant_id } },
          tenantId: tenant_id,
          isGroup: false
        }
      )
      response.fetch("id")
    end

    # Starts a new thread in a channel. Returns the thread's conversation ID
    # and the ID of its first message.
    def create_channel_thread(service_url:, channel_id:, tenant_id:, activity:)
      response = http.post(
        url(service_url, "v3/conversations"),
        {
          isGroup: true,
          channelData: { channel: { id: channel_id }, tenant: { id: tenant_id } },
          tenantId: tenant_id,
          activity: activity
        }
      )
      { conversation_id: response["id"], activity_id: response["activityId"] }
    end

    def send_activity(service_url:, conversation_id:, activity:)
      http.post(url(service_url, "v3/conversations/#{escape(conversation_id)}/activities"), activity)["id"]
    end

    def update_activity(service_url:, conversation_id:, activity_id:, activity:)
      http.put(
        url(service_url, "v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"),
        activity.merge(id: activity_id)
      )
    end

    private

    attr_reader :http

    def url(service_url, path)
      raise UntrustedServiceUrl.new("Refusing to call untrusted Teams service URL #{service_url.inspect}", status: 400) unless self.class.trusted_service_url?(service_url)

      "#{service_url.to_s.chomp('/')}/#{path}"
    end

    def escape(value)
      ERB::Util.url_encode(value.to_s)
    end
  end
end

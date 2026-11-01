module Microsoft
  # The few Microsoft Graph calls the Teams adapter needs, using application
  # permissions (see docs/teams-setup.md).
  class GraphClient
    BASE_URL = "https://graph.microsoft.com/v1.0".freeze
    USER_FIELDS = "id,displayName,mail,userPrincipalName,userType,accountEnabled".freeze
    MAX_PAGES = 20

    def initialize(http: HttpClient.new(scope: TokenProvider::GRAPH_SCOPE))
      @http = http
    end

    def user(user_id)
      http.get(url("users/#{escape(user_id)}"), params: { "$select" => USER_FIELDS })
    end

    # Windows or IANA name, whatever the user's mailbox uses. Nil if unknown.
    def user_time_zone(user_id)
      http.get(url("users/#{escape(user_id)}/mailboxSettings/timeZone"))["value"].presence
    rescue ApiError => error
      Rails.logger.info "Couldn't read Teams time zone for #{user_id}: #{error.message}"
      nil
    end

    def search_users(query, limit:)
      params = { "$select" => USER_FIELDS, "$top" => limit.clamp(1, 999) }
      if query.present?
        term = query.to_s.strip.gsub("'", "''")
        params["$filter"] = %w[displayName givenName surname mail userPrincipalName].map { |field| "startswith(#{field},'#{term}')" }.join(" or ")
      end

      collect(url("users"), params, limit)
    end

    def teams(limit:)
      collect(url("teams"), { "$select" => "id,displayName" }, limit)
    end

    def channels(team_id)
      collect(url("teams/#{escape(team_id)}/channels"), { "$select" => "id,displayName,membershipType" }, 1_000)
    end

    def channel_members(team_id, channel_id)
      collect(url("teams/#{escape(team_id)}/channels/#{escape(channel_id)}/members"), {}, 5_000)
    end

    # Installs the org's Teams app for a user so the bot can message them.
    def install_app_for_user(user_id, catalog_app_id)
      http.post(
        url("users/#{escape(user_id)}/teamwork/installedApps"),
        { "teamsApp@odata.bind" => "#{BASE_URL}/appCatalogs/teamsApps/#{escape(catalog_app_id)}" }
      )
    rescue ApiError => error
      raise unless error.status == 409 # already installed
    end

    private

    attr_reader :http

    def collect(first_url, params, limit)
      records = []
      next_url = first_url
      page_params = params

      MAX_PAGES.times do
        page = http.get(next_url, params: page_params)
        records.concat(Array(page["value"]))
        next_url = page["@odata.nextLink"]
        page_params = nil
        break if next_url.blank? || records.size >= limit
      end

      records.first(limit)
    end

    def url(path)
      "#{BASE_URL}/#{path}"
    end

    def escape(value)
      ERB::Util.url_encode(value.to_s)
    end
  end
end

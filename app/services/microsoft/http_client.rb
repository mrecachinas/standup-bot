module Microsoft
  # JSON over HTTPS with an app token, retrying on 429 and once on 401.
  class HttpClient
    MAX_RATE_LIMIT_RETRIES = 3

    def initialize(scope:, token_provider: TokenProvider.instance, connection: nil)
      @scope = scope
      @token_provider = token_provider
      @connection = connection
    end

    def get(url, params: nil, headers: {})
      request(:get, url, params: params, headers: headers)
    end

    def post(url, body, headers: {})
      request(:post, url, body: body, headers: headers)
    end

    def put(url, body, headers: {})
      request(:put, url, body: body, headers: headers)
    end

    def request(method, url, body: nil, params: nil, headers: {})
      rate_limit_retries = 0
      reauthenticated = false

      begin
        response = timed(method, url) do
          connection.run_request(method, url, body && JSON.generate(body), request_headers(headers)) do |request|
            request.params.update(params) if params
          end
        end

        if response.status == 401 && !reauthenticated
          reauthenticated = true
          token_provider.invalidate(scope)
          raise RetryRequest
        end

        if response.status == 429
          raise ChatPlatform::RateLimitedError.new("Microsoft API rate limit reached", retry_after: retry_after(response, rate_limit_retries)) if rate_limit_retries >= MAX_RATE_LIMIT_RETRIES

          StandupMetrics.track("teams.rate_limited", url: URI(url).path)
          sleep retry_after(response, rate_limit_retries)
          rate_limit_retries += 1
          raise RetryRequest
        end

        parse(response)
      rescue RetryRequest
        retry
      rescue Faraday::Error => error
        raise TransientApiError, "Couldn't reach Microsoft (#{error.class})"
      end
    end

    private

    RetryRequest = Class.new(StandardError)

    attr_reader :scope, :token_provider

    # Times each attempt as a microsoft.api_request event, tagged with the
    # host (Graph or the Bot Connector) and the response status.
    def timed(method, url)
      tags = { method: method.to_s.upcase, host: (URI.parse(url.to_s).host rescue nil) }
      StandupMetrics.measure("microsoft.api_request", tags) do
        yield.tap { |response| tags[:status] = response.status }
      end
    end

    def request_headers(extra)
      {
        "Authorization" => "Bearer #{token_provider.token(scope)}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }.merge(extra)
    end

    def parse(response)
      body = response.body.present? ? JSON.parse(response.body) : {}
      return body if response.success?

      error = body.is_a?(Hash) ? body["error"] : nil
      code = error.is_a?(Hash) ? error["code"] : error || body["errorCode"]
      message = error.is_a?(Hash) ? error["message"] : body["message"]
      raise error_class(response).new("Microsoft API returned #{response.status}#{" (#{code})" if code}: #{message.to_s.truncate(200)}", status: response.status, code: code)
    rescue JSON::ParserError
      raise error_class(response).new("Microsoft API returned #{response.status} with an unreadable body", status: response.status) unless response.success?

      {}
    end

    def error_class(response)
      response.status >= 500 ? TransientApiError : ApiError
    end

    def retry_after(response, attempt)
      seconds = response.headers["Retry-After"].to_i
      seconds.positive? ? seconds : 2**attempt
    end

    def connection
      @connection ||= Faraday.new(request: { timeout: 15, open_timeout: 5 })
    end
  end
end

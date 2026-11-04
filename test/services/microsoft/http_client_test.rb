require "test_helper"

class Microsoft::HttpClientTest < ActiveSupport::TestCase
  class RecordingSubscriber
    attr_reader :events

    def initialize
      @events = []
    end

    def emit(event)
      @events << event if event[:name] == "microsoft.api_request"
    end
  end

  class FakeTokens
    attr_reader :invalidated

    def initialize
      @count = 0
      @invalidated = []
    end

    def token(_scope)
      @count += 1
      "token-#{@count}"
    end

    def invalidate(scope)
      @invalidated << scope
    end
  end

  setup do
    @stubs = Faraday::Adapter::Test::Stubs.new
    @tokens = FakeTokens.new
    @client = Microsoft::HttpClient.new(
      scope: "scope",
      token_provider: @tokens,
      connection: Faraday.new { |builder| builder.adapter(:test, @stubs) }
    )
    Microsoft::HttpClient.any_instance.stubs(:sleep)
    @subscriber = RecordingSubscriber.new
    Rails.event.subscribe(@subscriber)
  end

  teardown { Rails.event.unsubscribe(@subscriber) }

  test "sends a bearer token and parses JSON" do
    @stubs.post("https://graph.example/things") do |env|
      assert_equal "Bearer token-1", env.request_headers["Authorization"]
      assert_equal({ "name" => "x" }, JSON.parse(env.body))
      [ 201, { "Content-Type" => "application/json" }, '{"id":"1"}' ]
    end

    assert_equal({ "id" => "1" }, @client.post("https://graph.example/things", { name: "x" }))
  end

  test "retries after a 429 using Retry-After" do
    calls = 0
    @stubs.get("https://graph.example/users") do
      calls += 1
      calls == 1 ? [ 429, { "Retry-After" => "2" }, "" ] : [ 200, {}, '{"value":[]}' ]
    end
    Microsoft::HttpClient.any_instance.expects(:sleep).with(2)

    assert_equal({ "value" => [] }, @client.get("https://graph.example/users"))
    assert_equal 2, calls
  end

  test "raises RateLimitedError after repeated 429s" do
    @stubs.get("https://graph.example/users") { [ 429, {}, "" ] }

    assert_raises(ChatPlatform::RateLimitedError) { @client.get("https://graph.example/users") }
  end

  test "refreshes the token once after a 401" do
    calls = 0
    @stubs.get("https://graph.example/me") do |env|
      calls += 1
      calls == 1 ? [ 401, {}, "" ] : [ 200, {}, %({"token":"#{env.request_headers['Authorization']}"}) ]
    end

    assert_equal "Bearer token-2", @client.get("https://graph.example/me")["token"]
    assert_equal [ "scope" ], @tokens.invalidated
  end

  test "maps error responses to ApiError with status and code" do
    @stubs.get("https://graph.example/users/x") { [ 404, {}, '{"error":{"code":"Request_ResourceNotFound","message":"Nope"}}' ] }

    error = assert_raises(Microsoft::ApiError) { @client.get("https://graph.example/users/x") }
    assert_equal 404, error.status
    assert_equal "Request_ResourceNotFound", error.code
    assert error.not_found?
  end

  test "5xx responses and unreachable hosts are transient, so jobs retry them" do
    @stubs.get("https://graph.example/busy") { [ 503, {}, '{"error":{"code":"ServiceUnavailable","message":"Busy"}}' ] }
    @stubs.get("https://graph.example/missing") { [ 404, {}, "{}" ] }
    @stubs.get("https://graph.example/down") { raise Faraday::ConnectionFailed, "down" }

    assert_raises(Microsoft::TransientApiError) { @client.get("https://graph.example/busy") }
    assert_raises(Microsoft::TransientApiError) { @client.get("https://graph.example/down") }
    error = assert_raises(Microsoft::ApiError) { @client.get("https://graph.example/missing") }
    assert_not_kind_of Microsoft::TransientApiError, error
  end

  test "measures each attempt and counts unsuccessful responses as errors" do
    calls = 0
    @stubs.get("https://graph.example/users") do
      calls += 1
      calls == 1 ? [ 429, { "Retry-After" => "1" }, "" ] : [ 200, {}, "{}" ]
    end
    @stubs.get("https://graph.example/busy") { [ 503, {}, "" ] }

    @client.get("https://graph.example/users")
    assert_raises(Microsoft::TransientApiError) { @client.get("https://graph.example/busy") }

    payloads = @subscriber.events.map { |event| event[:payload].slice(:method, :host, :status, :outcome) }
    assert_equal [
      { method: "GET", host: "graph.example", status: 429, outcome: "error" },
      { method: "GET", host: "graph.example", status: 200, outcome: "success" },
      { method: "GET", host: "graph.example", status: 503, outcome: "error" }
    ], payloads
    assert @subscriber.events.all? { |event| event[:payload][:duration_ms].is_a?(Float) }
  end
end

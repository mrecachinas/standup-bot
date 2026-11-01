require "test_helper"
require_relative "../../support/teams_test_helper"

class Microsoft::TokenProviderTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    enable_teams!
    @stubs = Faraday::Adapter::Test::Stubs.new
    @provider = Microsoft::TokenProvider.new(connection: Faraday.new { |builder| builder.adapter(:test, @stubs) })
  end

  test "fetches a client-credentials token for the tenant and caches it" do
    calls = 0
    @stubs.post("/#{TEAMS_TENANT_ID}/oauth2/v2.0/token") do |env|
      calls += 1
      form = Rack::Utils.parse_query(env.body)
      assert_equal "client_credentials", form["grant_type"]
      assert_equal TEAMS_APP_ID, form["client_id"]
      assert_equal Microsoft::TokenProvider::GRAPH_SCOPE, form["scope"]
      [ 200, {}, '{"access_token":"abc","expires_in":3600}' ]
    end

    2.times { assert_equal "abc", @provider.token(Microsoft::TokenProvider::GRAPH_SCOPE) }
    assert_equal 1, calls
  end

  test "raises a clear error when credentials are rejected" do
    @stubs.post("/#{TEAMS_TENANT_ID}/oauth2/v2.0/token") { [ 401, {}, '{"error":"invalid_client"}' ] }

    error = assert_raises(Microsoft::ApiError) { @provider.token(Microsoft::TokenProvider::GRAPH_SCOPE) }
    assert_match "invalid_client", error.message
  end

  test "raises when Teams isn't configured" do
    Rails.application.config.stubs(:teams).returns({})

    assert_raises(Microsoft::ApiError) { @provider.token(Microsoft::TokenProvider::GRAPH_SCOPE) }
  end
end

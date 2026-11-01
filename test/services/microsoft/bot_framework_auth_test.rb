require "test_helper"
require_relative "../../support/teams_test_helper"

class Microsoft::BotFrameworkAuthTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    @auth = Microsoft::BotFrameworkAuth.new(keys: StaticKeys.new(jwks_for), app_id: TEAMS_APP_ID)
  end

  def valid_claims(overrides = {})
    { iss: "https://api.botframework.com", aud: TEAMS_APP_ID, serviceurl: TEAMS_SERVICE_URL }.merge(overrides)
  end

  def verify(token, service_url: TEAMS_SERVICE_URL, channel_id: "msteams")
    @auth.verify!("Bearer #{token}", service_url: service_url, channel_id: channel_id)
  end

  test "accepts a correctly signed Bot Connector token" do
    payload = verify(signed_token(valid_claims))

    assert_equal TEAMS_APP_ID, payload["aud"]
  end

  test "reads the lowercase serviceurl claim real Bot Connector tokens use" do
    claims = valid_claims
    assert claims.key?(:serviceurl)
    assert_not claims.key?(:serviceUrl)

    assert verify(signed_token(claims))
  end

  test "accepts a service URL that differs only by a trailing slash" do
    assert verify(signed_token(valid_claims), service_url: TEAMS_SERVICE_URL.chomp("/"))
  end

  test "rejects tokens for another bot" do
    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { verify(signed_token(valid_claims(aud: "someone-else"))) }
  end

  test "rejects tokens from another issuer" do
    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { verify(signed_token(valid_claims(iss: "https://evil.example"))) }
  end

  test "rejects expired tokens" do
    token = signed_token(valid_claims(exp: 10.minutes.ago.to_i, nbf: 20.minutes.ago.to_i))

    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { verify(token) }
  end

  test "rejects tokens signed by an unknown key" do
    token = signed_token(valid_claims, key: OpenSSL::PKey::RSA.generate(2048))

    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { verify(token) }
  end

  test "rejects a service URL that doesn't match the token" do
    error = assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) do
      verify(signed_token(valid_claims), service_url: "https://smba.trafficmanager.net/evil/")
    end

    assert_match "serviceurl", error.message
  end

  test "rejects keys that aren't endorsed for the channel" do
    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) do
      verify(signed_token(valid_claims), channel_id: "webchat")
    end
  end

  test "rejects missing or malformed authorization headers" do
    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { @auth.verify!(nil, service_url: TEAMS_SERVICE_URL, channel_id: "msteams") }
    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) { @auth.verify!("Basic abc", service_url: TEAMS_SERVICE_URL, channel_id: "msteams") }
  end

  test "rejects everything when Teams isn't configured" do
    auth = Microsoft::BotFrameworkAuth.new(keys: StaticKeys.new(jwks_for), app_id: nil)

    assert_raises(Microsoft::BotFrameworkAuth::Unauthorized) do
      auth.verify!("Bearer #{signed_token(valid_claims)}", service_url: TEAMS_SERVICE_URL, channel_id: "msteams")
    end
  end
end

class Microsoft::OpenIdKeysTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @keys = Microsoft::OpenIdKeys.new(metadata_url: "https://login.example/openid")
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "unknown key IDs refresh the keys at most once per interval" do
    @keys.expects(:fetch_keys).twice.returns({ "keys" => [ { "kid" => "a" } ] })

    @keys.document
    3.times { @keys.document(force: true) }

    travel Microsoft::OpenIdKeys::MIN_REFRESH_INTERVAL + 1.second do
      @keys.document(force: true)
    end
  end
end

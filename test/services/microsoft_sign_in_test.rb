require "test_helper"
require_relative "../support/teams_test_helper"

class MicrosoftSignInTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    enable_teams!
    @stubs = Faraday::Adapter::Test::Stubs.new
    @stubs.post("/#{TEAMS_TENANT_ID}/oauth2/v2.0/token") { [ 200, {}, '{"id_token":"id-token"}' ] }
    @verifier = mock("verifier")
    @sign_in = MicrosoftSignIn.new(connection: Faraday.new { |builder| builder.adapter(:test, @stubs) }, verifier: @verifier)
    ChatPlatform::TeamsAdapter.any_instance.stubs(:user_profile).returns(ChatPlatform::UserProfile.new(id: TEAMS_USER_ID, guest: false, deleted: false))
  end

  def claims(overrides = {})
    { "oid" => TEAMS_USER_ID.upcase, "tid" => TEAMS_TENANT_ID, "name" => "Tess Teams", "preferred_username" => "tess@contoso.com" }.merge(overrides)
  end

  test "builds an authorize URL pinned to the tenant with state and nonce" do
    uri = URI.parse(MicrosoftSignIn.authorize_url(redirect_uri: "https://app.example/auth/microsoft/callback", state: "s", nonce: "n"))
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "/#{TEAMS_TENANT_ID}/oauth2/v2.0/authorize", uri.path
    assert_equal TEAMS_APP_ID, query["client_id"]
    assert_equal %w[s n], query.values_at("state", "nonce")
    assert_equal "openid profile email", query["scope"]
  end

  test "returns the person's object ID as their identity" do
    @verifier.expects(:verify!).with("id-token", nonce: "n").returns(claims)

    identity = @sign_in.identity_for(code: "code", redirect_uri: "https://app.example/cb", nonce: "n")

    assert_equal TEAMS_USER_ID, identity.user_id
    assert_equal "Tess Teams", identity.name
    assert_equal "tess@contoso.com", identity.email
    assert_not identity.email_verified, "Entra email isn't trusted for linking without xms_edov"
  end

  test "trusts the email only when the tenant marks it verified" do
    @verifier.expects(:verify!).returns(claims("email" => "tess@contoso.com", "xms_edov" => true))

    assert @sign_in.identity_for(code: "code", redirect_uri: "https://app.example/cb", nonce: "n").email_verified
  end

  test "refuses guests" do
    @verifier.expects(:verify!).returns(claims)
    ChatPlatform::TeamsAdapter.any_instance.stubs(:user_profile).returns(ChatPlatform::UserProfile.new(id: TEAMS_USER_ID, guest: true))

    error = assert_raises(MicrosoftSignIn::Error) { @sign_in.identity_for(code: "code", redirect_uri: "https://app.example/cb", nonce: "n") }
    assert_match "Guest", error.message
  end

  test "turns token verification failures into sign-in errors" do
    @verifier.expects(:verify!).raises(Microsoft::IdTokenVerifier::Invalid, "That Microsoft account belongs to a different organization.")

    error = assert_raises(MicrosoftSignIn::Error) { @sign_in.identity_for(code: "code", redirect_uri: "https://app.example/cb", nonce: "n") }
    assert_match "different organization", error.message
  end

  test "isn't configured without a tenant" do
    Rails.application.config.stubs(:teams).returns({ app_id: TEAMS_APP_ID, app_password: "secret" })

    assert_not MicrosoftSignIn.configured?
  end
end

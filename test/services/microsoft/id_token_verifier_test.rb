require "test_helper"
require_relative "../../support/teams_test_helper"

class Microsoft::IdTokenVerifierTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    @verifier = Microsoft::IdTokenVerifier.new(tenant_id: TEAMS_TENANT_ID, client_id: TEAMS_APP_ID, keys: StaticKeys.new(jwks_for(endorsements: nil)))
  end

  def claims(overrides = {})
    {
      iss: "https://login.microsoftonline.com/#{TEAMS_TENANT_ID}/v2.0",
      aud: TEAMS_APP_ID,
      tid: TEAMS_TENANT_ID,
      oid: TEAMS_USER_ID,
      nonce: "nonce-1",
      name: "Tess Teams"
    }.merge(overrides)
  end

  test "returns claims for a valid token" do
    assert_equal TEAMS_USER_ID, @verifier.verify!(signed_token(claims), nonce: "nonce-1")["oid"]
  end

  test "rejects another tenant" do
    other_tenant = "12345678-1234-1234-1234-123456789012"
    token = signed_token(claims(tid: other_tenant))

    error = assert_raises(Microsoft::IdTokenVerifier::Invalid) { @verifier.verify!(token, nonce: "nonce-1") }
    assert_match "different organization", error.message
  end

  test "rejects a nonce mismatch or missing nonce" do
    assert_raises(Microsoft::IdTokenVerifier::Invalid) { @verifier.verify!(signed_token(claims), nonce: "other") }
    assert_raises(Microsoft::IdTokenVerifier::Invalid) { @verifier.verify!(signed_token(claims), nonce: nil) }
  end

  test "rejects the wrong audience or issuer" do
    assert_raises(Microsoft::IdTokenVerifier::Invalid) { @verifier.verify!(signed_token(claims(aud: "other-app")), nonce: "nonce-1") }
    assert_raises(Microsoft::IdTokenVerifier::Invalid) { @verifier.verify!(signed_token(claims(iss: "https://login.microsoftonline.com/common/v2.0")), nonce: "nonce-1") }
  end
end

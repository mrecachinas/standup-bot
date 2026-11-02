# Turns on Teams with fake credentials, and builds Bot Framework style tokens.
module TeamsTestHelper
  TEAMS_APP_ID = "11111111-2222-3333-4444-555555555555".freeze
  TEAMS_TENANT_ID = "99999999-8888-7777-6666-555555555555".freeze
  TEAMS_SERVICE_URL = "https://smba.trafficmanager.net/teams/".freeze
  TEAMS_TEAM_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee".freeze
  TEAMS_CHANNEL = "#{TEAMS_TEAM_ID}|19:standup@thread.tacv2".freeze
  TEAMS_USER_ID = "0f0f0f0f-1111-2222-3333-444444444444".freeze

  def enable_teams!(**overrides)
    config = {
      app_id: TEAMS_APP_ID,
      app_password: "teams-test-secret",
      tenant_id: TEAMS_TENANT_ID,
      service_url: TEAMS_SERVICE_URL
    }.merge(overrides)
    Rails.application.config.stubs(:teams).returns(config)
  end

  def create_teams_standup!(name: "Teams Standup", user_id: TEAMS_USER_ID)
    standup = Standup.create!(
      name: name,
      platform: "teams",
      platform_channel: TEAMS_CHANNEL,
      platform_channel_name: "Engineering › Standup",
      questions: [ "Yesterday?", "Today?" ],
      intro: "Morning!"
    )
    standup.standup_participants.create!(platform_user_id: user_id, display_name: "Tess Teams", cached_timezone: "UTC")
    standup
  end

  # Generated once per test process; RSA key generation is slow.
  def self.rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def rsa_key
    TeamsTestHelper.rsa_key
  end

  def jwks_for(key = rsa_key, kid: "test-key", endorsements: [ "msteams" ])
    jwk = JWT::JWK.new(key, kid: kid).export.transform_keys(&:to_s)
    jwk["endorsements"] = endorsements if endorsements
    { "keys" => [ jwk ] }
  end

  def signed_token(claims, key: rsa_key, kid: "test-key")
    JWT.encode({ exp: 5.minutes.from_now.to_i, nbf: 1.minute.ago.to_i }.merge(claims), key, "RS256", kid: kid)
  end

  # Stands in for Microsoft::OpenIdKeys without network access.
  class StaticKeys
    def initialize(document)
      @document = document
    end

    def loader
      ->(_options) { JWT::JWK::Set.new(@document) }
    end

    def key(kid)
      @document["keys"].find { |key| key["kid"] == kid }
    end
  end
end

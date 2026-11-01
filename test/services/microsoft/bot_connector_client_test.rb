require "test_helper"
require_relative "../../support/teams_test_helper"

class Microsoft::BotConnectorClientTest < ActiveSupport::TestCase
  include TeamsTestHelper

  setup do
    enable_teams!
    @http = mock("http")
    @client = Microsoft::BotConnectorClient.new(http: @http)
  end

  test "only trusts Microsoft's https service URLs" do
    assert Microsoft::BotConnectorClient.trusted_service_url?("https://smba.trafficmanager.net/teams/")
    assert Microsoft::BotConnectorClient.trusted_service_url?("https://smba.infra.gcc.teams.microsoft.com/teams")
    assert_not Microsoft::BotConnectorClient.trusted_service_url?("http://smba.trafficmanager.net/teams/")
    assert_not Microsoft::BotConnectorClient.trusted_service_url?("https://trafficmanager.net.evil.example/")
    assert_not Microsoft::BotConnectorClient.trusted_service_url?("https://attacker.trafficmanager.net/teams/")
    assert_not Microsoft::BotConnectorClient.trusted_service_url?("not a url")
  end

  test "refuses to send the bot token to an untrusted service URL" do
    @http.expects(:post).never

    assert_raises(Microsoft::BotConnectorClient::UntrustedServiceUrl) do
      @client.send_activity(service_url: "https://evil.example/", conversation_id: "a:1", activity: {})
    end
  end

  test "creates a personal conversation with the user's object ID" do
    @http.expects(:post).with(
      "https://smba.trafficmanager.net/teams/v3/conversations",
      has_entries(members: [ { id: TEAMS_USER_ID } ], isGroup: false, tenantId: TEAMS_TENANT_ID, bot: { id: "28:#{TEAMS_APP_ID}" })
    ).returns({ "id" => "a:conversation" })

    assert_equal "a:conversation", @client.create_personal_conversation(service_url: TEAMS_SERVICE_URL, user_id: TEAMS_USER_ID, tenant_id: TEAMS_TENANT_ID)
  end

  test "starts channel threads and returns the thread and message IDs" do
    @http.expects(:post).with(
      "https://smba.trafficmanager.net/teams/v3/conversations",
      has_entries(isGroup: true, channelData: { channel: { id: "19:c@thread.tacv2" }, tenant: { id: TEAMS_TENANT_ID } })
    ).returns({ "id" => "19:c@thread.tacv2;messageid=42", "activityId" => "42" })

    thread = @client.create_channel_thread(service_url: TEAMS_SERVICE_URL, channel_id: "19:c@thread.tacv2", tenant_id: TEAMS_TENANT_ID, activity: { type: "message" })

    assert_equal({ conversation_id: "19:c@thread.tacv2;messageid=42", activity_id: "42" }, thread)
  end

  test "escapes conversation and activity IDs in URLs" do
    @http.expects(:put).with(
      "https://smba.trafficmanager.net/teams/v3/conversations/19%3Ac%40thread.tacv2%3Bmessageid%3D42/activities/42",
      has_entries(id: "42", text: "updated")
    )

    @client.update_activity(service_url: TEAMS_SERVICE_URL, conversation_id: "19:c@thread.tacv2;messageid=42", activity_id: "42", activity: { text: "updated" })
  end
end

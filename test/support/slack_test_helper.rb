# Slack stubs shared across tests. Included in every ActiveSupport::TestCase by test_helper.rb.
module SlackTestHelper
  # Makes SlackClient.instance return +client+ (a fresh mock by default) and returns it.
  def stub_slack_client(client = mock("SlackClient"))
    SlackClient.stubs(:instance).returns(client)
    client
  end

  def stub_slack_status
    SlackIntegrationService.any_instance.stubs(:configuration_status).returns(slack_status)
    SlackIntegrationService.any_instance.stubs(:connection_status).returns(
      SlackIntegrationService::Result.new(status: "ok", message: "Slack API authentication succeeded.", metadata: { "team" => "Example" })
    )
    SlackIntegrationService.any_instance.stubs(:discover_channels).returns(SlackIntegrationService::Result.new(status: "ok", records: []))
    SlackIntegrationService.any_instance.stubs(:discover_users).returns(SlackIntegrationService::Result.new(status: "ok", records: []))
  end

  def slack_status
    {
      configured: true,
      installation: { message: "Slack app bot token is configured." },
      credentials: {
        bot_token: { label: "Bot token", configured: true, required: true, message: "Bot token is configured." },
        signing_secret: { label: "Signing secret", configured: true, required: true, message: "Signing secret is configured." },
        client_id: { label: "Client ID", configured: false, required: false, message: "Client ID is optional." },
        client_secret: { label: "Client secret", configured: false, required: false, message: "Client secret is optional." }
      }
    }
  end
end

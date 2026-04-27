require "test_helper"

class Manager::SlackIntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    stub_status
  end

  test "requires authentication" do
    get manager_slack_integration_path

    assert_redirected_to new_session_path
  end

  test "manager sees Slack status without secret values and only manageable standups" do
    sign_in(@manager, "manager-access-token")

    get manager_slack_integration_path

    assert_response :success
    assert_includes response.body, "Slack app status"
    assert_includes response.body, "Slack API authentication succeeded"
    assert_includes response.body, @owned_standup.name
    assert_not_includes response.body, @unowned_standup.name
    assert_not_includes response.body, "xoxb-secret"
    assert_not_includes response.body, "signing-secret"
  end

  test "channel discovery surfaces Slack records" do
    SlackIntegrationService.any_instance.expects(:discover_channels)
      .with(query: "gen")
      .returns(SlackIntegrationService::Result.new(status: "ok", records: [ { "id" => "C123", "label" => "#general" } ], message: "Found 1 Slack channel(s)."))
    sign_in(@manager, "manager-access-token")

    get manager_slack_integration_path, params: { discover: "channels", channel_query: "gen" }

    assert_response :success
    assert_includes response.body, "#general"
    assert_includes response.body, "C123"
  end

  private

  def stub_status
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

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

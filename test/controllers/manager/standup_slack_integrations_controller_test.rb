require "test_helper"

class Manager::StandupSlackIntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @participant = standup_participants(:one)
    stub_status
  end

  test "requires authentication" do
    get manager_standup_slack_setup_path(@owned_standup)

    assert_redirected_to new_session_path
  end

  test "manager cannot view unowned standup Slack setup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_slack_setup_path(@unowned_standup)

    assert_response :forbidden
  end

  test "admin can view unowned standup Slack setup" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_slack_setup_path(@unowned_standup)

    assert_response :success
    assert_includes response.body, @unowned_standup.name
  end

  test "manager can discover and select a Slack channel" do
    SlackIntegrationService.any_instance.expects(:discover_channels)
      .with(query: "daily")
      .returns(SlackIntegrationService::Result.new(status: "ok", records: [ { "id" => "CDAILY", "name" => "daily", "label" => "#daily" } ]))
    sign_in(@manager, "manager-access-token")

    get manager_standup_slack_setup_path(@owned_standup), params: { discover: "channels", channel_query: "daily" }

    assert_response :success
    assert_includes response.body, "#daily"
    assert_includes response.body, "Use channel"
  end

  test "manager updates standup Slack channel and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'slack.channel.update').count", 1 do
      patch manager_standup_slack_setup_channel_path(@owned_standup),
        params: { channel_id: "CNEWCHAN", channel_name: "new-channel" }
    end

    assert_redirected_to manager_standup_slack_setup_path(@owned_standup, channel_updated: "1")
    assert_equal "CNEWCHAN", @owned_standup.reload.slack_channel
    audit_log = AuditLog.where(action: "slack.channel.update").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal "daily-standup", audit_log.metadata["previous_channel"]
    assert_equal "CNEWCHAN", audit_log.metadata["slack_channel"]
  end

  test "manager adds discovered Slack user as participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'slack.participant.add').count", 1 do
        post manager_standup_slack_setup_participants_path(@owned_standup),
          params: { slack_id: "UDISC1", slack_name: "Discovered User" }
      end
    end

    assert_redirected_to manager_standup_slack_setup_path(@owned_standup, participant_added: "1")
    participant = @owned_standup.standup_participants.find_by!(slack_id: "UDISC1")
    assert_equal "Discovered User", participant.slack_name
  end

  test "manager adds Slack user by username" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("@discovered", fallback_name: nil)
      .returns(SlackUserResolver::ResolvedUser.new(slack_id: "UDISC2", slack_name: "Discovered By Username", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post manager_standup_slack_setup_participants_path(@owned_standup),
        params: { slack_user: "@discovered" }
    end

    assert_redirected_to manager_standup_slack_setup_path(@owned_standup, participant_added: "1")
    assert_equal "Discovered By Username", @owned_standup.standup_participants.find_by!(slack_id: "UDISC2").slack_name
  end

  test "manager removes participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", -1 do
      assert_difference "AuditLog.where(action: 'slack.participant.remove').count", 1 do
        delete manager_standup_slack_setup_participant_path(@owned_standup, @participant)
      end
    end

    assert_redirected_to manager_standup_slack_setup_path(@owned_standup, participant_removed: "1")
    audit_log = AuditLog.where(action: "slack.participant.remove").order(:created_at).last
    assert_equal @participant.slack_id, audit_log.metadata["slack_id"]
  end

  test "manager sends test standup message and writes audit log" do
    SlackIntegrationService.any_instance.expects(:test_message)
      .with(@owned_standup)
      .returns(SlackIntegrationService::Result.new(status: "ok", message: "Sent", metadata: { "channel" => "C123", "ts" => "123.456" }))
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'slack.test_message.send').count", 1 do
      post manager_standup_slack_setup_test_message_path(@owned_standup)
    end

    assert_redirected_to manager_standup_slack_setup_path(@owned_standup, test_message_sent: "1")
    audit_log = AuditLog.where(action: "slack.test_message.send").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal @owned_standup.slack_channel, audit_log.metadata["slack_channel"]
    assert_equal({ "channel" => "C123", "ts" => "123.456" }, audit_log.metadata["slack_response"])
  end

  test "test message error is actionable and audited" do
    SlackIntegrationService.any_instance.expects(:test_message)
      .with(@owned_standup)
      .returns(SlackIntegrationService::Result.new(
        status: "error",
        message: "Slack bot is not a member of the configured channel.",
        action: "Invite the Slack bot to the channel, then retry.",
        error_code: "not_in_channel"
      ))
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'slack.test_message.failure').count", 1 do
      post manager_standup_slack_setup_test_message_path(@owned_standup)
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Invite the Slack bot"
    audit_log = AuditLog.where(action: "slack.test_message.failure").order(:created_at).last
    assert_equal "not_in_channel", audit_log.metadata["error_code"]
  end

  test "manager cannot send test message for unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      post manager_standup_slack_setup_test_message_path(@unowned_standup)
    end

    assert_response :forbidden
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

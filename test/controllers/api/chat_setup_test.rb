require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::ChatSetupTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @participant = standup_participants(:one)
    stub_slack_status
  end

  test "requires authentication" do
    get api_standup_chat_setup_path(@owned_standup), as: :json

    assert_response :unauthorized
  end

  test "manager sees the Slack setup for an owned standup" do
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(@owned_standup), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal({ "key" => "slack", "label" => "Slack", "icon" => "hash" }, body["platform"])
    assert_equal "daily-standup", body.dig("channel", "platform_channel")
    assert_equal @owned_standup.channel_reference, body.dig("channel", "channel_reference")
    assert_equal PlatformSerializer.copy_for(:slack, :channel_id_placeholder), body.dig("copy", "channel_id_placeholder")
    assert_equal PlatformSerializer.copy_for(:slack, :user_placeholder), body.dig("copy", "user_placeholder")

    status = body["integration_status"]
    assert_equal "Slack app status", status["title"]
    assert_equal "Connected", status["status_label"]
    assert_equal %w[bot_token signing_secret client_id client_secret], status["credentials"].map { |credential| credential["key"] }
    assert_equal "Slack API authentication succeeded.", status.dig("connection", "message")
    assert_equal [ { "key" => "team", "label" => "Team", "value" => "Example" } ], status.dig("connection", "metadata")

    assert_includes body["participants"].map { |participant| participant["platform_user_id"] }, @participant.platform_user_id
    assert_nil body["channel_result"]
    assert_nil body["user_result"]
  end

  test "manager can't view the setup for a standup they don't own" do
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(@unowned_standup), as: :json

    assert_response :forbidden
  end

  test "admin can view any standup's setup" do
    sign_in(@admin, "admin-access-token")

    get api_standup_chat_setup_path(@unowned_standup), as: :json

    assert_response :success
    assert_equal @unowned_standup.name, response.parsed_body.dig("standup", "name")
  end

  test "manager discovers Slack channels without private ones" do
    SlackIntegrationService.any_instance.expects(:discover_channels)
      .with(query: "daily", include_private: false)
      .returns(SlackIntegrationService::Result.new(status: "ok", records: [ { "id" => "CDAILY", "name" => "daily", "label" => "#daily", "is_member" => true } ]))
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(@owned_standup, discover: "channels", channel_query: "daily"), as: :json

    assert_response :success
    result = response.parsed_body["channel_result"]
    assert result["success"]
    record = result["records"].sole
    assert_equal "CDAILY", record["id"]
    assert_equal "#daily", record["label"]
    assert_equal "channel", record["kind"]
    assert_equal "CDAILY · bot is a member", record["detail"]
    assert_equal "daily", response.parsed_body["channel_query"]
  end

  test "admins see private channels, with a session or a token" do
    SlackIntegrationService.any_instance.expects(:discover_channels).with(query: nil, include_private: true).twice
      .returns(SlackIntegrationService::Result.new(status: "ok", records: []))

    get api_standup_chat_setup_path(@owned_standup, discover: "channels"), headers: token_headers, as: :json
    assert_response :success

    sign_in(@admin, "admin-access-token")
    get api_standup_chat_setup_path(@owned_standup, discover: "channels"), as: :json
    assert_response :success
  end

  test "user discovery returns people" do
    SlackIntegrationService.any_instance.expects(:discover_users).with(query: "jane")
      .returns(SlackIntegrationService::Result.new(status: "ok", records: [ { "id" => "UJANE", "name" => "jane", "label" => "Jane", "tz" => "Europe/London", "avatar_url" => "javascript:alert(1)" } ]))
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(@owned_standup, user_query: "jane"), as: :json

    record = response.parsed_body.dig("user_result", "records").sole
    assert_equal "user", record["kind"]
    assert_equal "UJANE · @jane · Europe/London", record["detail"]
    assert_nil record["avatar_url"]
  end

  test "discovery failures come back with the next step" do
    SlackIntegrationService.any_instance.expects(:discover_users)
      .returns(SlackIntegrationService::Result.new(status: "error", message: "Slack bot token is not configured.", action: "Set SLACK_BOT_TOKEN and restart the app.", error_code: "missing_bot_token"))
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(@owned_standup, discover: "users"), as: :json

    result = response.parsed_body["user_result"]
    assert_not result["success"]
    assert_equal "Set SLACK_BOT_TOKEN and restart the app.", result["action"]
    assert_nil result["records"]
  end

  test "manager updates the Slack channel and writes an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'slack.channel.update').count", 1 do
      patch channel_api_standup_chat_setup_path(@owned_standup), params: { channel_id: "CNEWCHAN", channel_name: "new-channel" }, as: :json
    end

    assert_response :success
    assert_equal "Slack channel updated.", response.parsed_body["notice"]
    assert_equal "CNEWCHAN", response.parsed_body.dig("channel", "platform_channel")
    assert_equal "CNEWCHAN", @owned_standup.reload.platform_channel
    audit_log = AuditLog.where(action: "slack.channel.update").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal "daily-standup", audit_log.metadata["previous_channel"]
    assert_equal "CNEWCHAN", audit_log.metadata["platform_channel"]
  end

  test "a blank channel is rejected" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch channel_api_standup_chat_setup_path(@owned_standup), params: { channel_id: " " }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "Select a Slack channel or enter a channel ID." ], response.parsed_body["errors"]
    assert_equal [ "Select a Slack channel or enter a channel ID." ], response.parsed_body.dig("field_errors", "channel_id")
  end

  test "manager adds a discovered Slack user and writes an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'slack.participant.add').count", 1 do
        post participants_api_standup_chat_setup_path(@owned_standup), params: { platform_user_id: "UDISC1", display_name: "Discovered User" }, as: :json
      end
    end

    assert_response :success
    assert_equal "Participant added.", response.parsed_body["notice"]
    assert_equal "UDISC1", response.parsed_body.dig("participant", "platform_user_id")
    assert_equal "Discovered User", @owned_standup.standup_participants.find_by!(platform_user_id: "UDISC1").display_name
  end

  test "manager adds a Slack user by username" do
    ChatUserResolver.any_instance.expects(:resolve)
      .with("@discovered", fallback_name: nil)
      .returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UDISC2", display_name: "Discovered By Username", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post participants_api_standup_chat_setup_path(@owned_standup), params: { slack_user: "@discovered" }, as: :json
    end

    assert_response :success
    assert_equal "Discovered By Username", @owned_standup.standup_participants.find_by!(platform_user_id: "UDISC2").display_name
  end

  test "a user that can't be resolved is a 422" do
    ChatUserResolver.any_instance.expects(:resolve).raises(ChatUserResolver::ResolutionError, "No Slack user matched \"ghost\".")
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupParticipant.count" do
      post participants_api_standup_chat_setup_path(@owned_standup), params: { user: "ghost" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "No Slack user matched \"ghost\".", response.parsed_body["error"]
  end

  test "manager removes a participant and writes an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", -1 do
      assert_difference "AuditLog.where(action: 'slack.participant.remove').count", 1 do
        delete participant_api_standup_chat_setup_path(@owned_standup, participant_id: @participant.id), as: :json
      end
    end

    assert_response :success
    assert_equal "Participant removed.", response.parsed_body["notice"]
    audit_log = AuditLog.where(action: "slack.participant.remove").order(:created_at).last
    assert_equal @participant.platform_user_id, audit_log.metadata["platform_user_id"]
  end

  test "manager sends a test message and writes an audit log" do
    SlackIntegrationService.any_instance.expects(:test_message)
      .with(@owned_standup)
      .returns(SlackIntegrationService::Result.new(status: "ok", message: "Sent", metadata: { "channel" => "C123", "ts" => "123.456" }))
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'slack.test_message.send').count", 1 do
      post test_message_api_standup_chat_setup_path(@owned_standup), as: :json
    end

    assert_response :success
    assert_equal "Test standup message sent.", response.parsed_body["notice"]
    assert response.parsed_body.dig("test_message", "success")
    audit_log = AuditLog.where(action: "slack.test_message.send").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal @owned_standup.platform_channel, audit_log.metadata["platform_channel"]
    assert_equal({ "channel" => "C123", "ts" => "123.456" }, audit_log.metadata["slack_response"])
  end

  test "a failed test message is actionable and audited" do
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
      post test_message_api_standup_chat_setup_path(@owned_standup), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "Invite the Slack bot to the channel, then retry.", response.parsed_body.dig("test_message", "action")
    audit_log = AuditLog.where(action: "slack.test_message.failure").order(:created_at).last
    assert_equal "not_in_channel", audit_log.metadata["error_code"]
  end

  test "manager can't change a standup they don't own" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "AuditLog.count", "StandupParticipant.count" ] do
      post test_message_api_standup_chat_setup_path(@unowned_standup), as: :json
      assert_response :forbidden

      patch channel_api_standup_chat_setup_path(@unowned_standup), params: { channel_id: "CNOPE" }, as: :json
      assert_response :forbidden

      post participants_api_standup_chat_setup_path(@unowned_standup), params: { platform_user_id: "UNOPE" }, as: :json
      assert_response :forbidden

      delete participant_api_standup_chat_setup_path(@unowned_standup, participant_id: standup_participants(:three).id), as: :json
      assert_response :forbidden
    end
  end

  test "a bearer token updates the channel, audited as its user" do
    patch channel_api_standup_chat_setup_path(@unowned_standup), params: { channel_id: "CTOKEN" }, headers: token_headers, as: :json

    assert_response :success
    log = AuditLog.where(action: "slack.channel.update").order(:created_at).last
    assert_equal users(:admin), log.actor
  end

  test "Teams standups are labeled for Teams and find Teams channels" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    TeamsIntegrationService.any_instance.stubs(:connection_status).returns(ChatIntegrationService::Result.new(status: "ok", message: "ok", metadata: {}))
    TeamsIntegrationService.any_instance.expects(:discover_channels).with(query: nil, include_private: false).returns(
      ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => TEAMS_CHANNEL, "label" => "Engineering › Standup" } ])
    )
    sign_in(@manager, "manager-access-token")

    get api_standup_chat_setup_path(standup, discover: "channels"), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal({ "key" => "teams", "label" => "Microsoft Teams", "icon" => "people" }, body["platform"])
    assert_equal "Microsoft Teams app status", body.dig("integration_status", "title")
    assert_equal TeamsIntegrationService::CREDENTIALS.map { |credential| credential[:key].to_s }, body.dig("integration_status", "credentials").map { |credential| credential["key"] }
    assert_equal PlatformSerializer.copy_for(:teams, :channel_id_placeholder), body.dig("copy", "channel_id_placeholder")
    assert_equal [ "Engineering › Standup" ], body.dig("channel_result", "records").map { |record| record["label"] }
    assert_not_includes response.body, "teams-test-secret"
  end

  test "Teams channel updates are audited under teams" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    TeamsIntegrationService.any_instance.stubs(:connection_status).returns(ChatIntegrationService::Result.new(status: "ok", message: "ok", metadata: {}))
    sign_in(@manager, "manager-access-token")
    new_channel = "#{TEAMS_TEAM_ID}|19:other@thread.tacv2"

    assert_difference "AuditLog.where(action: 'teams.channel.update').count", 1 do
      patch channel_api_standup_chat_setup_path(standup), params: { channel_id: new_channel, channel_name: "Engineering › Other" }, as: :json
    end

    assert_response :success
    assert_equal "Microsoft Teams channel updated.", response.parsed_body["notice"]
    assert_equal "Engineering › Other", standup.reload.platform_channel_name

    patch channel_api_standup_chat_setup_path(standup), params: { channel_id: "not a channel" }, as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body["field_errors"].key?("platform_channel")
  end
end

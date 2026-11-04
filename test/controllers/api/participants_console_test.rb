require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::ParticipantsConsoleTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @participant = standup_participants(:one)
  end

  test "requires authentication" do
    get api_standup_participants_path(@owned_standup), as: :json

    assert_response :unauthorized
  end

  test "manager sees the console roster for an owned standup" do
    @participant.update!(cached_timezone: "America/New_York", cached_timezone_updated_at: Time.current, vacation_until: Date.current)
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@owned_standup, view: "console"), as: :json

    assert_response :success
    body = response.parsed_body
    row = body["participants"].find { |participant| participant["id"] == @participant.id }
    assert_equal "John Doe", row["display_name"]
    assert_equal "U123456", row["platform_user_id"]
    assert_equal "America/New_York", row["timezone_label"]
    assert row["timezone_synced"]
    assert_equal "fresh", row["timezone_cache_status"]
    assert_equal "Away through #{Date.current.iso8601}", row["vacation_status"]
    assert_not row["available_today"]
    assert_equal "Active", row["status_label"]
    assert_equal "success", row["status_tone"]
    assert_nil row["holiday_status"]

    assert_equal @owned_standup.standup_participants.count, body.dig("summary", "participant_count")
    assert_equal @owned_standup.standup_participants.active.count, body.dig("summary", "active_count")
    assert_equal "slack", body.dig("platform", "key")
    assert_equal PlatformSerializer.copy_for(:slack, :user_placeholder), body.dig("platform", "copy", "user_placeholder")
    assert_equal @owned_standup.name, body.dig("standup", "name")
    assert_equal "daily-standup", body.dig("sync_defaults", "channel")
    assert_equal false, body.dig("sync_defaults", "deactivate_missing")

    managers = body["managers"]
    assert_equal [ @manager.id ], managers.map { |manager| manager["id"] }
    assert managers.first["current_user"]
    assert_equal "Manager", managers.first["role_label"]
    assert_not managers.first["can_remove"]
    assert_equal({ "minimum_managers" => 1, "can_remove_managers" => false, "only_admins_manage" => false }, body["manager_rules"])
  end

  test "roster marks participants who manage the standup" do
    @manager.link_identity!(:slack, @participant.platform_user_id)
    other = User.for_participant!(standup_participants(:two))
    @owned_standup.standup_ownerships.create!(user: other, role: "manager")
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@owned_standup, view: "console"), as: :json

    rows = response.parsed_body["participants"].index_by { |participant| participant["platform_user_id"] }
    assert rows["U123456"]["manager"]
    assert_equal @manager.id, rows["U123456"]["manager_user_id"]
    assert rows["U123456"]["can_remove_manager"]
    assert_not rows["U123456"]["can_make_manager"]
    assert_equal other.id, rows["U234567"]["manager_user_id"]
    assert_not rows["U456789"]["manager"]
    assert rows["U456789"]["can_make_manager"]
    assert response.parsed_body["managers"].all? { |manager| manager["can_remove"] }
  end

  test "roster shows today's holiday" do
    Standup.stubs(:holiday_on?).returns(true)
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@owned_standup, view: "console"), as: :json

    body = response.parsed_body
    assert body.dig("summary", "holiday_today")
    assert_equal [ "Holiday today" ], body["participants"].map { |participant| participant["holiday_status"] }.uniq
  end

  test "plain index keeps the admin shape" do
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@owned_standup), as: :json

    assert_response :success
    assert_equal [ "participants" ], response.parsed_body.keys
    assert_not response.parsed_body["participants"].first.key?("manager")
  end

  test "manager cannot view unowned standup participants" do
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@unowned_standup, view: "console"), as: :json

    assert_response :forbidden
  end

  test "admin and token can view unowned standup participants" do
    sign_in(@admin, "admin-access-token")
    get api_standup_participants_path(@unowned_standup, view: "console"), as: :json
    assert_response :success
    assert_includes response.parsed_body["participants"].map { |participant| participant["display_name"] }, "Alice Johnson"
    reset!

    get api_standup_participants_path(@unowned_standup, view: "console"), headers: token_headers, as: :json
    assert_response :success
    assert_includes response.parsed_body["participants"].map { |participant| participant["display_name"] }, "Alice Johnson"
    assert response.parsed_body["managers"].none? { |manager| manager["current_user"] }
  end

  test "manager creates participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'standup_participant.create').count", 1 do
        post api_standup_participants_path(@owned_standup),
          params: { participant: { platform_user_id: "UCREATE1", display_name: "Created User", cached_timezone: "UTC", active: true } },
          as: :json
      end
    end

    assert_response :created
    assert_equal "UCREATE1", response.parsed_body.dig("participant", "platform_user_id")
    assert_equal "Added Created User to #{@owned_standup.name}.", response.parsed_body["notice"]
    participant = @owned_standup.standup_participants.find_by!(platform_user_id: "UCREATE1")

    audit_log = AuditLog.where(action: "standup_participant.create").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal participant, audit_log.auditable
    assert_equal @owned_standup.id, audit_log.metadata["standup_id"]
    assert_equal "UCREATE1", audit_log.metadata.dig("attributes", "platform_user_id")
  end

  test "lookup resolves a Slack username" do
    ChatUserResolver.any_instance.expects(:resolve)
      .with("@created", fallback_name: "")
      .returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UCREATE2", display_name: "Created From Slack", cached_timezone: "America/New_York"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post api_standup_participants_path(@owned_standup),
        params: { lookup: true, participant: { platform_user_id: "@created", display_name: "", active: true } },
        as: :json
    end

    assert_response :created
    participant = @owned_standup.standup_participants.find_by!(platform_user_id: "UCREATE2")
    assert_equal "Created From Slack", participant.display_name
    assert_equal "America/New_York", participant.cached_timezone
  end

  test "without lookup, admin creates don't hit the chat platform" do
    ChatUserResolver.any_instance.expects(:resolve).never

    post api_standup_participants_path(@owned_standup),
      params: { participant: { platform_user_id: "UADMIN9", display_name: "" } },
      headers: token_headers,
      as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body.dig("field_errors", "display_name").present?
  end

  test "lookup failures come back as base errors" do
    ChatUserResolver.any_instance.expects(:resolve).raises(ChatUserResolver::ResolutionError, "No Slack user matched \"@nobody\".")
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
      post api_standup_participants_path(@owned_standup),
        params: { lookup: true, participant: { platform_user_id: "@nobody" } },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "No Slack user matched \"@nobody\"." ], response.parsed_body["errors"]
    assert_equal [ "No Slack user matched \"@nobody\"." ], response.parsed_body.dig("field_errors", "base")
  end

  test "Teams lookup resolves through Microsoft 365" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    TeamsIntegrationService.any_instance.expects(:resolve_user).with("tess@contoso.com").returns(
      ChatIntegrationService::Result.new(status: "ok", records: [ { "id" => "1f1f1f1f-1111-2222-3333-444444444444", "label" => "Tess Two", "tz" => "Europe/London" } ])
    )
    sign_in(@manager, "manager-access-token")

    post api_standup_participants_path(standup),
      params: { lookup: true, participant: { platform_user_id: "tess@contoso.com", active: true } },
      as: :json

    assert_response :created
    assert_equal "1f1f1f1f-1111-2222-3333-444444444444", response.parsed_body.dig("participant", "platform_user_id")
    assert_equal "Tess Two", response.parsed_body.dig("participant", "display_name")
    assert_equal "Europe/London", response.parsed_body.dig("participant", "cached_timezone")
  end

  test "Teams roster uses Teams copy and rejects Slack IDs" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(standup, view: "console"), as: :json
    assert_equal "teams", response.parsed_body.dig("platform", "key")
    assert_equal PlatformSerializer.copy_for(:teams, :import_hint), response.parsed_body.dig("platform", "copy", "import_hint")

    post api_standup_participants_path(standup), params: { participant: { platform_user_id: "U123ABC", display_name: "Slack Person" } }, as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body.dig("field_errors", "platform_user_id").present?
  end

  test "create renders validation errors" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
      post api_standup_participants_path(@owned_standup),
        params: { participant: { platform_user_id: "UBADTZ", display_name: "Bad Timezone", cached_timezone: "Invalid/Zone", active: true } },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Cached timezone is not a valid timezone"
    assert_equal [ "is not a valid timezone" ], response.parsed_body.dig("field_errors", "cached_timezone")
  end

  test "manager updates participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup_participant.update').count", 1 do
      patch api_standup_participant_path(@owned_standup, @participant),
        params: {
          participant: {
            display_name: "Updated Participant",
            cached_timezone: "America/Chicago",
            active: false,
            vacation_until: Date.current.iso8601
          }
        },
        as: :json
    end

    assert_response :success
    assert_equal "Saved Updated Participant.", response.parsed_body["notice"]
    assert_equal Date.current.iso8601, response.parsed_body.dig("participant", "vacation_until")
    @participant.reload
    assert_equal "Updated Participant", @participant.display_name
    assert_equal "America/Chicago", @participant.cached_timezone
    assert_not @participant.active
    assert_equal Date.current, @participant.vacation_until

    audit_log = AuditLog.where(action: "standup_participant.update").order(:created_at).last
    assert_equal [ "John Doe", "Updated Participant" ], audit_log.metadata.dig("changes", "display_name")
  end

  test "update clears vacation with a blank date" do
    @participant.update!(vacation_until: Date.current)
    sign_in(@manager, "manager-access-token")

    patch api_standup_participant_path(@owned_standup, @participant), params: { participant: { vacation_until: "" } }, as: :json

    assert_response :success
    assert_nil @participant.reload.vacation_until
  end

  test "update renders validation errors" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch api_standup_participant_path(@owned_standup, @participant), params: { participant: { cached_timezone: "Nope/Zone" } }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Cached timezone is not a valid timezone"
  end

  test "manager removes participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", -1 do
      assert_difference "AuditLog.where(action: 'standup_participant.destroy').count", 1 do
        delete api_standup_participant_path(@owned_standup, @participant), as: :json
      end
    end

    assert_response :no_content
    audit_log = AuditLog.where(action: "standup_participant.destroy").order(:created_at).last
    assert_equal @participant.id, audit_log.auditable_id
    assert_equal @participant.platform_user_id, audit_log.metadata.dig("attributes", "platform_user_id")
    assert_equal @participant.platform_user_id, audit_log.metadata["platform_user_id"]
  end

  test "manager cannot mutate unowned participants" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
      post api_standup_participants_path(@unowned_standup),
        params: { participant: { platform_user_id: "UBLOCKED", display_name: "Blocked" } },
        as: :json
      assert_response :forbidden

      patch api_standup_participant_path(@unowned_standup, standup_participants(:three)),
        params: { participant: { display_name: "Blocked Update" } },
        as: :json
      assert_response :forbidden

      delete api_standup_participant_path(@unowned_standup, standup_participants(:three)), as: :json
      assert_response :forbidden

      post bulk_import_api_standup_participants_path(@unowned_standup), params: { participants_text: "UBULK9,Nope" }, as: :json
      assert_response :forbidden
    end
  end

  test "can't update a participant from another standup" do
    sign_in(@manager, "manager-access-token")

    patch api_standup_participant_path(@owned_standup, standup_participants(:three)), params: { participant: { display_name: "Nope" } }, as: :json

    assert_response :not_found
  end

  test "a bearer token updates participants, audited as its user" do
    patch api_standup_participant_path(@owned_standup, @participant), params: { participant: { active: false } }, headers: token_headers, as: :json

    assert_response :success
    audit_log = AuditLog.where(action: "standup_participant.update").order(:created_at).last
    assert_equal users(:admin), audit_log.actor
    assert_equal "access_token", audit_log.metadata["auth_method"]
  end

  test "bulk import creates participants and writes summary audit" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 2 do
      assert_difference "AuditLog.where(action: 'standup_participant.bulk_import').count", 1 do
        post bulk_import_api_standup_participants_path(@owned_standup),
          params: { participants_text: "UBULK1,Alice Bulk,America/New_York,true\nUBULK2,Bob Bulk,UTC,false" },
          as: :json
      end
    end

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body.dig("summary", "created_count")
    assert_equal [], body["errors"]
    assert_equal "Import finished: 2 added, 0 updated, 0 unchanged.", body["notice"]
    assert_equal "Alice Bulk", @owned_standup.standup_participants.find_by!(platform_user_id: "UBULK1").display_name
    assert_not @owned_standup.standup_participants.find_by!(platform_user_id: "UBULK2").active
  end

  test "bulk import resolves Slack usernames" do
    ChatUserResolver.any_instance.expects(:resolve)
      .with("@bulk", fallback_name: "Bulk User")
      .returns(ChatUserResolver::ResolvedUser.new(platform_user_id: "UBULK3", display_name: "Bulk User", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post bulk_import_api_standup_participants_path(@owned_standup), params: { participants_text: "@bulk,Bulk User,,true" }, as: :json
    end

    assert_response :success
    assert_equal "Bulk User", @owned_standup.standup_participants.find_by!(platform_user_id: "UBULK3").display_name
  end

  test "bulk import surfaces validation errors" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupParticipant.count" do
      post bulk_import_api_standup_participants_path(@owned_standup),
        params: { participants_text: "UBADIMPORT,Bad Import,Invalid/Zone,true" },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Line 1: Cached timezone is not a valid timezone"
    assert_equal 1, response.parsed_body.dig("summary", "error_count")
  end

  test "sync imports Slack channel members and can deactivate missing participants" do
    standup = Standup.create!(name: "Sync Standup", platform_channel: "sync-channel", questions: [ "Update?" ], schedule_type: "daily", respect_timezone: true)
    standup.standup_ownerships.create!(user: @manager)
    existing = StandupParticipant.create!(standup: standup, platform_user_id: "USYNC1", display_name: "Old Sync", active: true)
    missing = StandupParticipant.create!(standup: standup, platform_user_id: "USYNC2", display_name: "Missing Sync", active: true)

    @manager.link_identity!(:slack, "UMGRSYNC")
    slack_client = stub_slack_client
    slack_client.stubs(:channel_members).with("sync-channel").returns([ "UMGRSYNC", existing.platform_user_id, "USYNC3", "UBOTSYNC", "USLACKBOT" ])
    slack_client.stubs(:get_user_info).with("UMGRSYNC").returns(slack_user("m.grsync", deleted: true))
    slack_client.stubs(:get_user_info).with(existing.platform_user_id).returns(slack_user("synced.user", display_name: "Synced User", tz: "America/Los_Angeles"))
    slack_client.stubs(:get_user_info).with("USYNC3").returns(slack_user("new.sync", real_name: "New Sync", tz: "UTC"))
    slack_client.stubs(:get_user_info).with("UBOTSYNC").returns(slack_user("standup_bot", is_bot: true))
    slack_client.expects(:get_user_info).with("USLACKBOT").never
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'standup_participant.sync').count", 1 do
        post sync_api_standup_participants_path(standup), params: { channel: "sync-channel", deactivate_missing: "1" }, as: :json
      end
    end

    assert_response :success
    body = response.parsed_body
    assert_equal({ "created_count" => 1, "updated_count" => 1, "unchanged_count" => 0, "deactivated_count" => 1, "error_count" => 0 }, body["summary"])
    assert_equal "Synced Slack channel: 1 added, 1 updated, 0 unchanged, 1 marked inactive.", body["notice"]
    assert_equal "slack_sync", AuditLog.where(action: "standup_participant.sync").last.metadata["source"]
    assert_equal "Synced User", existing.reload.display_name
    assert_equal "America/Los_Angeles", existing.cached_timezone
    assert_not missing.reload.active
    assert_equal "New Sync", standup.standup_participants.find_by!(platform_user_id: "USYNC3").display_name
    assert_not standup.standup_participants.exists?(platform_user_id: "UBOTSYNC")
    assert_not standup.standup_participants.exists?(platform_user_id: "USLACKBOT")
    assert_not standup.standup_participants.exists?(platform_user_id: "UMGRSYNC")
  end

  test "an admin is told when Slack can't find the channel" do
    slack_client = stub_slack_client
    slack_client.expects(:channel_members).with("standup-bot-test")
      .raises(ChatPlatform::ChannelAccessError, "Slack couldn't find #standup-bot-test.")

    post sync_api_standup_participants_path(@owned_standup), params: { channel: "standup-bot-test" }, headers: token_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "Slack couldn't find #standup-bot-test." ], response.parsed_body["errors"]
  end

  test "sync surfaces Slack lookup errors without auditing" do
    @manager.link_identity!(:slack, "UMGRSYNC")
    slack_client = stub_slack_client
    slack_client.stubs(:channel_members).with("empty-channel").returns([ "UMGRSYNC" ])
    slack_client.stubs(:get_user_info).with("UMGRSYNC").returns(slack_user("bot", is_bot: true))
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      post sync_api_standup_participants_path(@owned_standup), params: { channel: "empty-channel" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "No Slack members were returned for that channel."
  end

  test "managers get the same answer for missing channels and ones they're not in" do
    @manager.link_identity!(:slack, "UOUTSIDER")
    slack_client = stub_slack_client
    slack_client.stubs(:channel_members).with("secret-channel").returns([ "USOMEONE" ])
    slack_client.stubs(:channel_members).with("no-such-channel")
      .raises(ChatPlatform::ChannelAccessError, "Slack couldn't find #no-such-channel.")
    slack_client.expects(:get_user_info).never
    sign_in(@manager, "manager-access-token")

    answers = %w[secret-channel no-such-channel].map do |channel|
      assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
        post sync_api_standup_participants_path(@owned_standup), params: { channel: channel }, as: :json
      end
      assert_response :unprocessable_entity
      response.parsed_body["errors"]
    end

    assert_equal [ [ "You can only sync people from a channel you're in." ] ] * 2, answers
  end

  test "managers can only sync people from channels they're in" do
    @manager.link_identity!(:slack, "UOUTSIDER")
    slack_client = stub_slack_client
    slack_client.expects(:channel_members).with("secret-channel").once.returns([ "USOMEONE" ])
    slack_client.expects(:get_user_info).never
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupParticipant.count" do
      post sync_api_standup_participants_path(@owned_standup), params: { channel: "secret-channel" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "You can only sync people from a channel you're in." ], response.parsed_body["errors"]
  end

  test "sync reports platform failures" do
    slack_client = stub_slack_client
    slack_client.expects(:channel_members).raises(StandardError, "boom")

    post sync_api_standup_participants_path(@owned_standup), headers: token_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "Unable to sync Slack channel. Check the channel and Slack app permissions, then try again." ], response.parsed_body["errors"]
  end

  test "an admin's token can sync any channel and syncs Teams channels" do
    enable_teams!
    standup = create_teams_standup!
    ChatPlatform::TeamsAdapter.any_instance.expects(:channel_member_ids).never
    ChatPlatform::TeamsAdapter.any_instance.expects(:channel_member_profiles).with(TEAMS_CHANNEL).returns([
      { "platform_user_id" => "2f2f2f2f-1111-2222-3333-444444444444", "display_name" => "New Teams", "cached_timezone" => "UTC" }
    ])

    post sync_api_standup_participants_path(standup), headers: token_headers, as: :json

    assert_response :success
    assert standup.standup_participants.exists?(platform_user_id: "2f2f2f2f-1111-2222-3333-444444444444")
    assert_equal "Synced Microsoft Teams channel: 1 added, 0 updated, 0 unchanged.", response.parsed_body["notice"]
    assert_equal "teams_sync", AuditLog.where(action: "standup_participant.sync").last.metadata["source"]
  end

  private

  def slack_user(name, display_name: nil, real_name: nil, tz: nil, deleted: false, is_bot: false)
    { "name" => name, "tz" => tz, "profile" => { "display_name" => display_name, "real_name" => real_name }, "deleted" => deleted, "is_bot" => is_bot }
  end
end

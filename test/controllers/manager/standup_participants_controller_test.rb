require "test_helper"

class Manager::StandupParticipantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    @participant = standup_participants(:one)
  end

  test "requires authentication" do
    get manager_standup_participants_path(@owned_standup)

    assert_redirected_to new_session_path
  end

  test "manager can view owned standup participants" do
    @participant.update!(cached_timezone: "America/New_York", cached_timezone_updated_at: Time.current, vacation_until: Date.current)
    sign_in(@manager, "manager-access-token")

    get manager_standup_participants_path(@owned_standup)

    assert_response :success
    assert_includes response.body, @participant.slack_name
    assert_includes response.body, @participant.slack_id
    assert_includes response.body, "America/New_York"
    assert_includes response.body, "Away through #{Date.current.iso8601}"
  end

  test "manager cannot view unowned standup participants" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_participants_path(@unowned_standup)

    assert_response :forbidden
  end

  test "admin can view unowned standup participants" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_participants_path(@unowned_standup)

    assert_response :success
    assert_includes response.body, standup_participants(:three).slack_name
  end

  test "manager creates participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'standup_participant.create').count", 1 do
        post manager_standup_participants_path(@owned_standup),
          params: {
            standup_participant: {
              slack_id: "UCREATE1",
              slack_name: "Created User",
              cached_timezone: "UTC",
              active: true
            }
          }
      end
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    participant = @owned_standup.standup_participants.find_by!(slack_id: "UCREATE1")
    assert_equal "Created User", participant.slack_name

    audit_log = AuditLog.where(action: "standup_participant.create").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal participant, audit_log.auditable
    assert_equal @owned_standup.id, audit_log.metadata["standup_id"]
  end

  test "manager can create participant from Slack username" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("@created", fallback_name: "")
      .returns(SlackUserResolver::ResolvedUser.new(slack_id: "UCREATE2", slack_name: "Created From Slack", cached_timezone: "America/New_York"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post manager_standup_participants_path(@owned_standup),
        params: {
          standup_participant: {
            slack_id: "@created",
            slack_name: "",
            active: true
          }
        }
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    participant = @owned_standup.standup_participants.find_by!(slack_id: "UCREATE2")
    assert_equal "Created From Slack", participant.slack_name
    assert_equal "America/New_York", participant.cached_timezone
  end

  test "create renders validation errors" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
      post manager_standup_participants_path(@owned_standup),
        params: {
          standup_participant: {
            slack_id: "UBADTZ",
            slack_name: "Bad Timezone",
            cached_timezone: "Invalid/Zone",
            active: true
          }
        }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Cached timezone is not a valid timezone"
  end

  test "manager updates participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'standup_participant.update').count", 1 do
      patch manager_standup_participant_path(@owned_standup, @participant),
        params: {
          standup_participant: {
            slack_name: "Updated Participant",
            cached_timezone: "America/Chicago",
            active: false,
            vacation_until: Date.current.iso8601
          }
        }
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    @participant.reload
    assert_equal "Updated Participant", @participant.slack_name
    assert_equal "America/Chicago", @participant.cached_timezone
    assert_not @participant.active
    assert_equal Date.current, @participant.vacation_until

    audit_log = AuditLog.where(action: "standup_participant.update").order(:created_at).last
    assert_equal [ "John Doe", "Updated Participant" ], audit_log.metadata.dig("changes", "slack_name")
  end

  test "manager removes participant and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", -1 do
      assert_difference "AuditLog.where(action: 'standup_participant.destroy').count", 1 do
        delete manager_standup_participant_path(@owned_standup, @participant)
      end
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    audit_log = AuditLog.where(action: "standup_participant.destroy").order(:created_at).last
    assert_equal @participant.id, audit_log.auditable_id
    assert_equal @participant.slack_id, audit_log.metadata.dig("attributes", "slack_id")
  end

  test "manager cannot mutate unowned participants" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupParticipant.count", "AuditLog.count" ] do
      post manager_standup_participants_path(@unowned_standup),
        params: { standup_participant: { slack_id: "UBLOCKED", slack_name: "Blocked" } }
    end
    assert_response :forbidden

    assert_no_difference "AuditLog.count" do
      patch manager_standup_participant_path(@unowned_standup, standup_participants(:three)),
        params: { standup_participant: { slack_name: "Blocked Update" } }
    end
    assert_response :forbidden
  end

  test "bulk import creates participants and writes summary audit" do
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 2 do
      assert_difference "AuditLog.where(action: 'standup_participant.bulk_import').count", 1 do
        post bulk_import_manager_standup_participants_path(@owned_standup),
          params: {
            participants_text: "UBULK1,Alice Bulk,America/New_York,true\nUBULK2,Bob Bulk,UTC,false"
          }
      end
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    assert_equal "Alice Bulk", @owned_standup.standup_participants.find_by!(slack_id: "UBULK1").slack_name
    assert_not @owned_standup.standup_participants.find_by!(slack_id: "UBULK2").active
  end

  test "bulk import resolves Slack usernames" do
    SlackUserResolver.any_instance.expects(:resolve)
      .with("@bulk", fallback_name: "Bulk User")
      .returns(SlackUserResolver::ResolvedUser.new(slack_id: "UBULK3", slack_name: "Bulk User", cached_timezone: "UTC"))
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      post bulk_import_manager_standup_participants_path(@owned_standup),
        params: { participants_text: "@bulk,Bulk User,,true" }
    end

    assert_redirected_to manager_standup_participants_path(@owned_standup)
    assert_equal "Bulk User", @owned_standup.standup_participants.find_by!(slack_id: "UBULK3").slack_name
  end

  test "bulk import surfaces validation errors" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupParticipant.count" do
      post bulk_import_manager_standup_participants_path(@owned_standup),
        params: { participants_text: "UBADIMPORT,Bad Import,Invalid/Zone,true" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Line 1: Cached timezone is not a valid timezone"
  end

  test "sync imports Slack channel members and can deactivate missing participants" do
    standup = Standup.create!(
      name: "Sync Standup",
      slack_channel: "sync-channel",
      questions: [ "Update?" ],
      schedule_type: "daily",
      respect_timezone: true
    )
    standup.standup_ownerships.create!(user: @manager)
    existing = StandupParticipant.create!(standup: standup, slack_id: "USYNC1", slack_name: "Old Sync", active: true)
    missing = StandupParticipant.create!(standup: standup, slack_id: "USYNC2", slack_name: "Missing Sync", active: true)

    slack_client = mock("SlackClient")
    slack_client.expects(:channel_member_profiles).with("sync-channel").returns([
      { "slack_id" => existing.slack_id, "slack_name" => "Synced User", "cached_timezone" => "America/Los_Angeles" },
      { "slack_id" => "USYNC3", "slack_name" => "New Sync", "cached_timezone" => "UTC" }
    ])
    SlackClient.expects(:instance).returns(slack_client)

    sign_in(@manager, "manager-access-token")

    assert_difference "StandupParticipant.count", 1 do
      assert_difference "AuditLog.where(action: 'standup_participant.sync').count", 1 do
        post sync_manager_standup_participants_path(standup),
          params: { channel: "sync-channel", deactivate_missing: "1" }
      end
    end

    assert_redirected_to manager_standup_participants_path(standup)
    assert_equal "Synced User", existing.reload.slack_name
    assert_equal "America/Los_Angeles", existing.cached_timezone
    assert_not missing.reload.active
    assert standup.standup_participants.exists?(slack_id: "USYNC3")
  end

  test "sync surfaces Slack lookup errors without auditing" do
    slack_client = mock("SlackClient")
    slack_client.expects(:channel_member_profiles).with("empty-channel").returns([])
    SlackClient.expects(:instance).returns(slack_client)
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      post sync_manager_standup_participants_path(@owned_standup),
        params: { channel: "empty-channel" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "No Slack members were returned for that channel."
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

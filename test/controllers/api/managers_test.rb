require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::ManagersTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  setup do
    @manager = users(:manager)
    @daily = standups(:daily)
    @weekly = standups(:weekly)
    @member = standup_participants(:two)
  end

  test "a standup's manager can make someone in it a manager" do
    sign_in(@manager, "manager-access-token")

    assert_difference [ "User.count", "@daily.standup_ownerships.count" ], 1 do
      post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json
    end

    assert_response :created
    promoted = User.find_by_identity(:slack, @member.platform_user_id)
    body = response.parsed_body
    assert_equal "Jane Smith can now manage #{@daily.name}.", body["notice"]
    assert_equal promoted.id, body.dig("manager", "id")
    assert_equal @member.platform_user_id, body.dig("manager", "platform_user_id")
    assert_equal "Manager", body.dig("manager", "role_label")
    assert body.dig("manager", "can_remove")
    assert_equal @member.id, body["participant_id"]
    assert promoted.can_manage_standup?(@daily)
    assert_not promoted.can_manage_standup?(@weekly)
    assert_not promoted.admin?

    audit_log = AuditLog.find_by!(action: "standup.manager.add", auditable: @daily)
    assert_equal @manager, audit_log.actor
    assert_equal promoted.id, audit_log.metadata["user_id"]
  end

  test "promoting someone who already manages is a no-op" do
    sign_in(@manager, "manager-access-token")
    post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json

    assert_no_difference "StandupOwnership.count" do
      post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json
    end

    assert_response :ok
  end

  test "promoting reuses an existing account for that Slack user" do
    users(:other_manager).link_identity!(:slack, @member.platform_user_id)
    sign_in(@manager, "manager-access-token")

    assert_no_difference "User.count" do
      post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json
    end

    assert users(:other_manager).can_manage_standup?(@daily)
  end

  test "turned-off accounts can't be promoted" do
    users(:inactive_manager).link_identity!(:slack, @member.platform_user_id)
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "StandupOwnership.count", "AuditLog.count" ] do
      post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "Jane Smith's account is turned off, so they can't manage standups." ], response.parsed_body["errors"]
  end

  test "managers can't promote people in a standup they don't manage" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post api_standup_managers_path(@weekly), params: { participant_id: standup_participants(:three).id }, as: :json
    end

    assert_response :forbidden
  end

  test "managers can't promote someone from another standup through their own" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post api_standup_managers_path(@daily), params: { participant_id: standup_participants(:three).id }, as: :json
    end

    assert_response :not_found
  end

  test "a manager can be removed, but not the last one" do
    sign_in(@manager, "manager-access-token")
    post api_standup_managers_path(@daily), params: { participant_id: @member.id }, as: :json
    promoted = User.find_by_identity(:slack, @member.platform_user_id)

    assert_difference "@daily.standup_ownerships.count", -1 do
      delete api_standup_manager_path(@daily, promoted), as: :json
    end
    assert_response :success
    assert_equal({ "can_manage" => true, "user_id" => promoted.id, "notice" => "Jane Smith no longer manages #{@daily.name}." }, response.parsed_body)
    assert AuditLog.exists?(action: "standup.manager.remove", auditable: @daily)
    assert_not promoted.reload.can_manage_standup?(@daily)

    assert_no_difference "@daily.standup_ownerships.count" do
      delete api_standup_manager_path(@daily, @manager), as: :json
    end
    assert_response :unprocessable_entity
    assert_equal [ "#{@daily.name} needs at least one manager." ], response.parsed_body["errors"]
  end

  test "stepping down reports that you lost access" do
    other = User.for_participant!(@member)
    @daily.standup_ownerships.create!(user: other, role: "manager")
    sign_in(@manager, "manager-access-token")

    delete api_standup_manager_path(@daily, @manager), as: :json

    assert_response :success
    assert_equal false, response.parsed_body["can_manage"]
    assert_equal "You no longer manage #{@daily.name}.", response.parsed_body["notice"]

    get api_standup_participants_path(@daily), as: :json
    assert_response :forbidden
  end

  test "removing someone who isn't a manager is not found" do
    sign_in(@manager, "manager-access-token")

    delete api_standup_manager_path(@daily, users(:other_manager)), as: :json

    assert_response :not_found
  end

  test "admins manage any standup's managers, with a session or a token" do
    sign_in(users(:admin), "admin-access-token")
    post api_standup_managers_path(@weekly), params: { participant_id: standup_participants(:three).id }, as: :json
    assert_response :created
    reset!

    alice = User.find_by_identity(:slack, standup_participants(:three).platform_user_id)
    delete api_standup_manager_path(@weekly, alice), headers: token_headers, as: :json
    assert_response :success
    assert response.parsed_body["can_manage"]
    audit_log = AuditLog.where(action: "standup.manager.remove").order(:created_at).last
    assert_equal users(:admin), audit_log.actor
    assert_equal "access_token", audit_log.metadata["auth_method"]
  end

  test "promoting a Teams participant links a Teams identity" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    participant = standup.standup_participants.first
    sign_in(@manager, "manager-access-token")

    post api_standup_managers_path(standup), params: { participant_id: participant.id }, as: :json

    assert_response :created
    promoted = User.find_by_identity(:teams, TEAMS_USER_ID)
    assert_equal TEAMS_USER_ID, response.parsed_body.dig("manager", "platform_user_id")
    assert promoted.can_manage_standup?(standup)
    assert_nil User.find_by_identity(:slack, TEAMS_USER_ID)
  end

  test "the console roster offers promotion for non-managers" do
    sign_in(@manager, "manager-access-token")

    get api_standup_participants_path(@daily, view: "console"), as: :json

    body = response.parsed_body
    assert_includes body["managers"].map { |manager| manager["name"] }, @manager.name
    member = body["participants"].find { |participant| participant["id"] == @member.id }
    assert member["can_make_manager"]
  end
end

require "test_helper"

class Manager::StandupManagersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @viewer = users(:viewer)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "manager can grant standup manager access to an active user" do
    sign_in(@manager, "manager-access-token")

    assert_difference [ "StandupOwnership.count", "AuditLog.where(action: 'standup_manager.grant').count" ], 1 do
      post manager_standup_managers_path(@owned_standup),
        params: { standup_manager: { user_id: @viewer.id } }
    end

    assert_redirected_to manager_standup_path(@owned_standup, manager_added: "1")
    ownership = @owned_standup.standup_ownerships.find_by!(user: @viewer)
    assert_equal "manager", ownership.role
    assert @viewer.can_manage_standup?(@owned_standup)
  end

  test "manager can revoke standup manager access when another manager remains" do
    ownership = @owned_standup.standup_ownerships.create!(user: @viewer, role: "manager")
    sign_in(@manager, "manager-access-token")

    assert_difference "StandupOwnership.count", -1 do
      assert_difference "AuditLog.where(action: 'standup_manager.revoke').count", 1 do
        delete manager_standup_manager_path(@owned_standup, ownership)
      end
    end

    assert_redirected_to manager_standup_path(@owned_standup, manager_removed: "1")
    assert_not @viewer.can_manage_standup?(@owned_standup)
  end

  test "manager cannot remove the last manager from a standup" do
    ownership = standup_ownerships(:daily_manager)
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      delete manager_standup_manager_path(@owned_standup, ownership)
    end

    assert_redirected_to manager_standup_path(@owned_standup, manager_error: "At least one manager must remain.")
  end

  test "manager cannot grant access for unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post manager_standup_managers_path(@unowned_standup),
        params: { standup_manager: { user_id: @viewer.id } }
    end

    assert_response :forbidden
  end

  test "requires choosing an active user" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post manager_standup_managers_path(@owned_standup),
        params: { standup_manager: { user_id: "" } }
    end

    assert_redirected_to manager_standup_path(@owned_standup, manager_error: "Choose an active user to grant access.")
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

require "test_helper"

class Manager::StandupManagersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @daily = standups(:daily)
    @weekly = standups(:weekly)
    @member = standup_participants(:two)
  end

  test "a standup's manager can make someone in it a manager" do
    sign_in(@manager, "manager-access-token")

    assert_difference [ "User.count", "@daily.standup_ownerships.count" ], 1 do
      post manager_standup_managers_path(@daily), params: { participant_id: @member.id }
    end

    assert_redirected_to manager_standup_participants_path(@daily)
    promoted = User.find_by_identity!(:slack, @member.platform_user_id)
    assert promoted.can_manage_standup?(@daily)
    assert_not promoted.can_manage_standup?(@weekly)
    assert_not promoted.admin?
    assert AuditLog.exists?(action: "standup.manager.add", auditable: @daily)
  end

  test "promoting reuses an existing account for that Slack user" do
    users(:other_manager).link_identity!(:slack, @member.platform_user_id)
    sign_in(@manager, "manager-access-token")

    assert_no_difference "User.count" do
      post manager_standup_managers_path(@daily), params: { participant_id: @member.id }
    end

    assert users(:other_manager).can_manage_standup?(@daily)
  end

  test "managers can't promote people in a standup they don't manage" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post manager_standup_managers_path(@weekly), params: { participant_id: standup_participants(:three).id }
    end

    assert_response :forbidden
  end

  test "managers can't promote someone from another standup through their own" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "StandupOwnership.count" do
      post manager_standup_managers_path(@daily), params: { participant_id: standup_participants(:three).id }
    end

    assert_response :not_found
  end

  test "a manager can be removed, but not the last one" do
    sign_in(@manager, "manager-access-token")
    post manager_standup_managers_path(@daily), params: { participant_id: @member.id }
    promoted = User.find_by_identity!(:slack, @member.platform_user_id)

    assert_difference "@daily.standup_ownerships.count", -1 do
      delete manager_standup_manager_path(@daily, promoted)
    end
    assert_not promoted.reload.can_manage_standup?(@daily)

    assert_no_difference "@daily.standup_ownerships.count" do
      delete manager_standup_manager_path(@daily, @manager)
    end
    follow_redirect!
    assert_includes response.body, "needs at least one manager"
  end

  test "participants page shows managers and promotion actions" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_participants_path(@daily)

    assert_response :success
    assert_select "#standup-managers", text: /#{Regexp.escape(@manager.name)}/
    assert_select "form[action='#{manager_standup_managers_path(@daily)}'] input[name='participant_id'][value='#{@member.id}']"
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

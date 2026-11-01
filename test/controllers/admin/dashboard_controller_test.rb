require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get admin_root_path

    assert_redirected_to new_session_path
  end

  test "managers cannot view the admin page" do
    sign_in(users(:manager), "manager-access-token")

    get admin_root_path

    assert_response :forbidden
  end

  test "admins see installation health, users, and recent changes" do
    sign_in(users(:admin), "admin-access-token")
    AuditLog.create!(action: "standup.update", actor: users(:admin), auditable: standups(:daily))

    get admin_root_path

    assert_response :success
    assert_select "#health-database h2", "Database"
    assert_select "#health-job-queue h2", "Job queue"
    assert_select "#health-slack-api h2", "Slack"
    assert_includes response.body, users(:manager).email
    assert_includes response.body, "standup update"
  end

  test "admin navigation is only shown to admins" do
    sign_in(users(:manager), "manager-access-token")
    get manager_standups_path
    assert_select "a.nav-item[href='#{admin_root_path}']", count: 0

    delete session_path
    sign_in(users(:admin), "admin-access-token")
    get manager_standups_path
    assert_select "a.nav-item[href='#{admin_root_path}']", count: 1
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

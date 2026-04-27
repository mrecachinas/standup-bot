require "test_helper"

class Manager::StandupAccessControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "manager can view response history for owned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup)

    assert_response :success
    assert_includes response.body, "Response history for #{@owned_standup.name}"
  end

  test "manager cannot view response history for unowned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@unowned_standup)

    assert_response :forbidden
  end

  test "manager can view participant stub for owned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_participants_path(@owned_standup)

    assert_response :success
    assert_includes response.body, "Participants"
    assert_includes response.body, "John Doe"
  end

  test "manager cannot view participant stub for unowned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_participants_path(@unowned_standup)

    assert_response :forbidden
  end

  test "admin can view analytics for any standup" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_analytics_path(@unowned_standup)

    assert_response :success
    assert_includes response.body, "Insights for #{@unowned_standup.name}"
  end

  test "manager cannot view analytics for unowned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_analytics_path(@unowned_standup)

    assert_response :forbidden
  end

  test "manager can view report stub for owned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_report_path(@owned_standup)

    assert_response :success
    assert_includes response.body, "Reports"
    assert_includes response.body, "Completion rate"
  end

  test "manager cannot view report stub for unowned standup" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_report_path(@unowned_standup)

    assert_response :forbidden
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "authenticates active users with access token" do
    user = User.authenticate(" manager@example.com ", "manager-access-token")

    assert_equal users(:manager), user
  end

  test "rejects invalid and inactive authentication" do
    assert_nil User.authenticate("manager@example.com", "wrong-token")
    assert_nil User.authenticate("inactive-manager@example.com", "inactive-access-token")
  end

  test "manager manages owned standups only" do
    manager = users(:manager)

    assert manager.can_manage_standup?(standups(:daily))
    assert_not manager.can_manage_standup?(standups(:weekly))
  end

  test "admin manages every standup" do
    admin = users(:admin)

    assert admin.can_manage_standup?(standups(:daily))
    assert admin.can_manage_standup?(standups(:weekly))
  end

  test "manageable standups scope is owner scoped" do
    manager_standups = Standup.manageable_by(users(:manager))

    assert_includes manager_standups, standups(:daily)
    assert_not_includes manager_standups, standups(:weekly)
    assert_equal Standup.count, Standup.manageable_by(users(:admin)).count
    assert_empty Standup.manageable_by(nil)
  end
end

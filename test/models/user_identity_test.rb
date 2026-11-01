require "test_helper"

class UserIdentityTest < ActiveSupport::TestCase
  test "links one identity per platform per user" do
    user = users(:manager)
    user.link_identity!(:slack, "UFIRST")
    user.link_identity!(:slack, "USECOND")

    assert_equal 1, user.identities.count
    assert_equal "USECOND", user.reload.platform_user_id_for(:slack)
  end

  test "platform user IDs are unique per platform" do
    users(:manager).link_identity!(:slack, "UTAKEN")
    duplicate = users(:admin).identities.build(platform: "slack", platform_user_id: "UTAKEN")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:platform_user_id], "has already been taken"
  end

  test "rejects unsupported platforms" do
    identity = users(:manager).identities.build(platform: "carrier_pigeon", platform_user_id: "X1")

    assert_not identity.valid?
    assert_includes identity.errors[:platform], "isn't a supported chat platform"
  end

  test "find_by_identity matches platform and ID" do
    users(:manager).link_identity!(:slack, "UFIND")

    assert_equal users(:manager), User.find_by_identity(:slack, "UFIND")
    assert_nil User.find_by_identity(:slack, "UMISSING")
    assert_nil User.find_by_identity(:slack, nil)
  end

  test "for_participant! creates an account tied to the standup's platform" do
    participant = standup_participants(:one)

    user = User.for_participant!(participant)

    assert_equal participant.platform_user_id, user.platform_user_id_for(:slack)
    assert user.placeholder_email?
    assert_equal user, User.for_participant!(participant)
  end

  test "deleting a user removes their identities" do
    user = users(:other_manager)
    user.link_identity!(:slack, "UGONE")

    assert_difference "UserIdentity.count", -1 do
      user.destroy!
    end
  end
end

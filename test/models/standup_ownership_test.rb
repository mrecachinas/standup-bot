require "test_helper"

class StandupOwnershipTest < ActiveSupport::TestCase
  test "prevents duplicate owners for a standup" do
    duplicate = StandupOwnership.new(standup: standups(:daily), user: users(:manager), role: "manager")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end
end

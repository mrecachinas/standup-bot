require "test_helper"

class MemberTest < ActiveSupport::TestCase
  test "finds members by platform and user ID" do
    member = Member.for(:slack, standup_participants(:one).platform_user_id)

    assert_equal "slack", member.platform
    assert_includes member.standups, standups(:daily)
  end

  test "returns nil for unknown platforms, blank IDs, and people in no standups" do
    assert_nil Member.for(:carrier_pigeon, standup_participants(:one).platform_user_id)
    assert_nil Member.for(:slack, nil)
    assert_nil Member.for(:slack, "UNOBODY")
  end

  test "ignores standups on other platforms" do
    participant = standup_participants(:three)
    participant.standup.update_column(:platform, "elsewhere")

    assert_nil Member.for(:slack, participant.platform_user_id)
  end
end

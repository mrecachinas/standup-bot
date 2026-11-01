require "test_helper"

class ChatPlatformTest < ActiveSupport::TestCase
  test "returns the Slack adapter by key, string, or default" do
    assert_instance_of ChatPlatform::SlackAdapter, ChatPlatform.for(:slack)
    assert_instance_of ChatPlatform::SlackAdapter, ChatPlatform.for("slack")
    assert_instance_of ChatPlatform::SlackAdapter, ChatPlatform.for(nil)
    assert_same ChatPlatform.for(:slack), ChatPlatform.for("slack")
  end

  test "raises for unknown platforms" do
    assert_raises(ChatPlatform::UnknownPlatform) { ChatPlatform.for(:carrier_pigeon) }
    assert_not ChatPlatform.supported?(:carrier_pigeon)
  end

  test "for_standup uses the standup's platform, defaulting to Slack" do
    assert_instance_of ChatPlatform::SlackAdapter, ChatPlatform.for_standup(standups(:daily))
    assert_instance_of ChatPlatform::SlackAdapter, ChatPlatform.for_standup(nil)
  end

  test "enabled lists configured adapters" do
    ChatPlatform::SlackAdapter.any_instance.stubs(:configured?).returns(true)
    assert_includes ChatPlatform.enabled.map(&:key), :slack

    ChatPlatform::SlackAdapter.any_instance.stubs(:configured?).returns(false)
    assert_not_includes ChatPlatform.enabled.map(&:key), :slack
  end
end

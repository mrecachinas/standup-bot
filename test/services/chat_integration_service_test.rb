require "test_helper"

class ChatIntegrationServiceTest < ActiveSupport::TestCase
  test "for picks the platform's service, defaulting to Slack when blank" do
    assert_instance_of SlackIntegrationService, ChatIntegrationService.for(:slack)
    assert_instance_of TeamsIntegrationService, ChatIntegrationService.for("teams")
    assert_instance_of SlackIntegrationService, ChatIntegrationService.for(nil)
  end

  test "for rejects platforms it doesn't know instead of assuming Slack" do
    assert_raises(ChatPlatform::UnknownPlatform) { ChatIntegrationService.for("discord") }
  end
end

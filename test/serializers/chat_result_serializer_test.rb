require "test_helper"

class ChatResultSerializerTest < ActiveSupport::TestCase
  test "labels ID fields so they don't repeat the name fields" do
    result = ChatIntegrationService::Result.new(
      status: "ok",
      message: "Slack API authentication succeeded.",
      metadata: { "team" => "Example", "team_id" => "T123", "user" => "standup_bot", "user_id" => "U999", "bot_id" => "B1", "url" => "https://example.slack.com/" }
    )

    labels = ChatResultSerializer.new(result).as_json[:metadata].to_h { |item| [ item[:key], item[:label] ] }

    assert_equal(
      { "team" => "Team", "team_id" => "Team ID", "user" => "User", "user_id" => "User ID", "bot_id" => "Bot ID", "url" => "URL" },
      labels
    )
  end
end

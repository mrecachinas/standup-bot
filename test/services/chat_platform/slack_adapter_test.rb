require "test_helper"
require_relative "../../support/chat_platform_adapter_contract"

class ChatPlatform::SlackAdapterTest < ActiveSupport::TestCase
  include ChatPlatformAdapterContract

  setup do
    @client = stub_slack_client
  end

  def adapter
    @adapter ||= ChatPlatform::SlackAdapter.new
  end

  test "send_direct_message returns a message ref from the Slack response" do
    @client.expects(:send_message).with("U123", "hi").returns({ "ok" => true, "channel" => "D123", "ts" => "1.2" })

    message = adapter.send_direct_message("U123", "hi")

    assert_equal "D123", message.channel
    assert_equal "1.2", message.id
  end

  test "send_message returns nil when Slack returns nothing" do
    @client.expects(:send_message).returns(nil)

    assert_nil adapter.send_message("C1", "hi")
  end

  test "post_standup_update renders mrkdwn" do
    @client.expects(:send_message).with("team", "*Ann's Standup Update:*\n\n*Q1*\nA1\n\n*Q2*\nA2")
      .returns({ "channel" => "C1", "ts" => "9.9" })

    message = adapter.post_standup_update("team", display_name: "Ann", answers: [ { question: "Q1", answer: "A1" }, { question: "Q2", answer: "A2" } ])

    assert_equal "9.9", message.id
  end

  test "update_standup_update sends text and section blocks" do
    @client.expects(:update_message).with do |channel, ts, text, blocks|
      channel == "team" && ts == "9.9" && text.include?("*Q1*\nA1") &&
        blocks.map { |block| block.dig(:text, :text) } == [ "*Ann's Standup Update:*", "*Q1*\nA1" ]
    end

    adapter.update_standup_update("team", "9.9", display_name: "Ann", answers: [ { question: "Q1", answer: "A1" } ])
  end

  test "post_report sends a standup summary" do
    @client.expects(:send_standup_summary).with("team", "summary", "bye").returns({ "channel" => "C1", "ts" => "1" })

    assert_equal "1", adapter.post_report("team", "summary", outro: "bye").id
  end

  test "send_selection passes the action id" do
    @client.expects(:send_standup_selection).with("D1", "Pick", [ { text: "A", value: 1 } ], action_id: "standup_start_selection")

    adapter.send_selection("D1", "Pick", [ { text: "A", value: 1 } ], action_id: "standup_start_selection")
  end

  test "user_profile maps Slack user info" do
    @client.expects(:get_user_info).with("U1").returns(
      "name" => "ann",
      "tz" => "America/Chicago",
      "avatar_url" => "https://example.com/ann.png",
      "profile" => { "display_name" => "", "real_name" => "Ann Lee", "email" => "ann@example.com" },
      "deleted" => false,
      "is_bot" => false,
      "is_restricted" => true
    )

    profile = adapter.user_profile("U1")

    assert_equal "U1", profile.id
    assert_equal "Ann Lee", profile.preferred_name
    assert_equal "America/Chicago", profile.timezone
    assert_equal "ann@example.com", profile.email
    assert profile.guest?
    assert_not profile.bot?
  end

  test "display_name_for prefers display name and falls back to Unknown User" do
    @client.stubs(:get_user_info).with("U1").returns("name" => "ann", "profile" => { "display_name" => "Annie" })
    @client.stubs(:get_user_info).with("U2").returns(nil)

    assert_equal "Annie", adapter.display_name_for("U1")
    assert_equal "Unknown User", adapter.display_name_for("U2")
  end

  test "discovery and connection calls delegate to the client" do
    @client.expects(:list_users).with(query: "a", limit: 5).returns([ { "id" => "U1" } ])
    @client.expects(:list_channels).with(query: "g", limit: 6, include_private: true).returns([ { "id" => "C1" } ])
    @client.expects(:channel_members).with("C1").returns([ "U1" ])
    @client.expects(:auth_test).returns({ "team_id" => "T1" })

    assert_equal [ { "id" => "U1" } ], adapter.search_users(query: "a", limit: 5)
    assert_equal [ { "id" => "C1" } ], adapter.list_channels(query: "g", limit: 6)
    assert_equal [ "U1" ], adapter.channel_member_ids("C1")
    assert_equal "T1", adapter.connection_status["team_id"]
  end

  test "channel_member_profiles skips bots, Slackbot, and deactivated people and uses friendly names" do
    @client.expects(:channel_members).with("C1").returns(%w[U1 U2 U3 UBOT UGONE USLACKBOT UMISSING])
    @client.stubs(:get_user_info).with("U1").returns(
      "name" => "m.recachinas", "tz" => "America/New_York", "avatar_url" => "https://avatars.slack-edge.com/u1.png",
      "profile" => { "display_name" => "Michael", "real_name" => "Michael Recachinas" }
    )
    @client.stubs(:get_user_info).with("U2").returns("name" => "erin.recachinas", "profile" => { "display_name" => "", "real_name" => "Erin Recachinas" })
    @client.stubs(:get_user_info).with("U3").returns("name" => "guest.user", "is_restricted" => true, "profile" => {})
    @client.stubs(:get_user_info).with("UBOT").returns("name" => "standup_bot", "is_bot" => true, "profile" => {})
    @client.stubs(:get_user_info).with("UGONE").returns("name" => "gone", "deleted" => true, "profile" => {})
    @client.stubs(:get_user_info).with("UMISSING").returns(nil)
    @client.expects(:get_user_info).with("USLACKBOT").never

    assert_equal(
      [
        { "platform_user_id" => "U1", "display_name" => "Michael", "cached_timezone" => "America/New_York", "avatar_url" => "https://avatars.slack-edge.com/u1.png" },
        { "platform_user_id" => "U2", "display_name" => "Erin Recachinas" },
        { "platform_user_id" => "U3", "display_name" => "guest.user" }
      ],
      adapter.channel_member_profiles("C1")
    )
  end

  test "validates Slack user IDs" do
    assert adapter.valid_user_id?("U123ABC")
    assert_not adapter.valid_user_id?("not-an-id")
  end

  test "formats channel references and selection blocks" do
    assert_equal "#team", adapter.channel_reference("team")

    blocks = adapter.selection_blocks("Pick", [ { text: "A", value: 1 } ], action_id: "standup_selection")
    assert_equal "standup_selection", blocks.last[:elements].first[:action_id]
    assert_equal "1", blocks.last[:elements].first[:options].first[:value]
  end
end

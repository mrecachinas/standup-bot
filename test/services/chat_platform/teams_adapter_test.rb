require "test_helper"
require_relative "../../support/chat_platform_adapter_contract"
require_relative "../../support/teams_test_helper"

class ChatPlatform::TeamsAdapterTest < ActiveSupport::TestCase
  include ChatPlatformAdapterContract
  include TeamsTestHelper

  setup do
    enable_teams!
    @connector = mock("connector")
    @graph = mock("graph")
  end

  def adapter
    @adapter ||= ChatPlatform::TeamsAdapter.new(connector: @connector, graph: @graph)
  end

  test "is configured only with app ID, secret, and tenant" do
    assert adapter.configured?

    Rails.application.config.stubs(:teams).returns({ app_id: TEAMS_APP_ID })
    assert_not adapter.configured?
  end

  test "DMs through a cached conversation" do
    ChatConversation.remember!(platform: :teams, platform_user_id: TEAMS_USER_ID, conversation_id: "a:cached", service_url: "https://smba.trafficmanager.net/emea/")
    @connector.expects(:create_personal_conversation).never
    @connector.expects(:send_activity).with(
      service_url: "https://smba.trafficmanager.net/emea/",
      conversation_id: "a:cached",
      activity: { type: "message", textFormat: "markdown", text: "hi" }
    ).returns("activity-1")

    message = adapter.send_direct_message(TEAMS_USER_ID.upcase, "hi")

    assert_equal "a:cached", message.channel
    assert_equal "activity-1", message.id
  end

  test "opens and remembers a conversation the first time" do
    @connector.expects(:create_personal_conversation).with(service_url: TEAMS_SERVICE_URL, user_id: TEAMS_USER_ID, tenant_id: TEAMS_TENANT_ID).returns("a:new")
    @connector.expects(:send_activity).with(has_entries(conversation_id: "a:new")).returns("activity-1")

    adapter.send_direct_message(TEAMS_USER_ID, "hi")

    assert_equal "a:new", ChatConversation.find_by!(platform: "teams", platform_user_id: TEAMS_USER_ID).conversation_id
  end

  test "installs the app and retries when Teams refuses a new chat" do
    enable_teams!(app_catalog_id: "catalog-app")
    sequence = sequence("install")
    @connector.expects(:create_personal_conversation).in_sequence(sequence).raises(Microsoft::ApiError.new("forbidden", status: 403))
    @graph.expects(:install_app_for_user).with(TEAMS_USER_ID, "catalog-app").in_sequence(sequence)
    @connector.expects(:create_personal_conversation).in_sequence(sequence).returns("a:installed")
    @connector.expects(:send_activity).returns("activity-1")

    assert_equal "a:installed", adapter.send_direct_message(TEAMS_USER_ID, "hi").channel
  end

  test "explains how to fix a missing install when it can't install itself" do
    @connector.expects(:create_personal_conversation).raises(Microsoft::ApiError.new("forbidden", status: 403))

    error = assert_raises(ChatPlatform::TeamsAdapter::NotInstalled) { adapter.send_direct_message(TEAMS_USER_ID, "hi") }
    assert_match "TEAMS_APP_CATALOG_ID", error.message
  end

  test "posts standup updates as a new channel thread in Teams markdown" do
    @connector.expects(:create_channel_thread).with do |args|
      args[:channel_id] == "19:standup@thread.tacv2" &&
        args[:activity][:text] == "**Tess** posted an update for **Daily**\n\n**Q1**\nA1"
    end.returns({ conversation_id: "19:standup@thread.tacv2;messageid=7", activity_id: "7" })

    message = adapter.post_standup_update(TEAMS_CHANNEL, display_name: "Tess", standup_name: "Daily", answers: [ { question: "Q1", answer: "A1" } ])

    assert_equal "7", message.id
  end

  test "edits a standup update in its thread" do
    @connector.expects(:update_activity).with(
      service_url: TEAMS_SERVICE_URL,
      conversation_id: "19:standup@thread.tacv2;messageid=7",
      activity_id: "7",
      activity: has_entries(text: includes("A2"))
    )

    adapter.update_standup_update(TEAMS_CHANNEL, "7", display_name: "Tess", standup_name: "Daily", answers: [ { question: "Q1", answer: "A2" } ])
  end

  test "replies in an existing conversation using its service URL" do
    ChatConversation.remember!(platform: :teams, platform_user_id: TEAMS_USER_ID, conversation_id: "a:chat", service_url: "https://smba.trafficmanager.net/amer/")
    @connector.expects(:send_activity).with(has_entries(service_url: "https://smba.trafficmanager.net/amer/", conversation_id: "a:chat")).returns("x")

    adapter.send_message("a:chat", "hello")
  end

  test "sends selections as an Adaptive Card" do
    @connector.expects(:send_activity).with do |args|
      card = args[:activity][:attachments].first
      card[:contentType] == ChatPlatform::TeamsAdapter::CARD_CONTENT_TYPE &&
        card.dig(:content, :actions, 0, :data) == { action_id: "standup_selection" } &&
        card.dig(:content, :body, 1, :choices) == [ { title: "Daily", value: "5" } ]
    end.returns("x")

    adapter.send_selection("a:chat", "Pick one", [ { text: "Daily", value: 5 } ], action_id: "standup_selection")
  end

  test "sends a single button as an Adaptive Card" do
    @connector.expects(:send_activity).with do |args|
      card = args[:activity][:attachments].first
      card.dig(:content, :body, 0, :text) == "You skipped **Daily**." &&
        card.dig(:content, :actions, 0) == { type: "Action.Submit", title: "Restart", data: { action_id: "standup_restart", standup_id: "5" } }
    end.returns("x")

    adapter.send_action("a:chat", "You skipped **Daily**.", button: { text: "Restart", value: 5 }, action_id: "standup_restart")
  end

  test "maps Graph users to profiles, including Windows time zones" do
    @graph.expects(:user).with(TEAMS_USER_ID).returns(
      "id" => TEAMS_USER_ID, "displayName" => "Tess Teams", "userPrincipalName" => "tess@contoso.com",
      "mail" => "tess@contoso.com", "userType" => "Member", "accountEnabled" => true
    )
    @graph.expects(:user_time_zone).with(TEAMS_USER_ID).returns("Pacific Standard Time")

    profile = adapter.user_profile(TEAMS_USER_ID)

    assert_equal "Tess Teams", profile.preferred_name
    assert_equal "America/Los_Angeles", profile.timezone
    assert_not profile.guest?
  end

  test "flags guests and returns nil for unknown users" do
    @graph.stubs(:user_time_zone).returns(nil)
    @graph.expects(:user).with("guest").returns("id" => "guest", "userType" => "Guest", "accountEnabled" => true)
    @graph.expects(:user).with("missing").raises(Microsoft::ApiError.new("nope", status: 404))

    assert adapter.user_profile("guest").guest?
    assert_nil adapter.user_profile("missing")
  end

  test "user search hides guests and disabled accounts" do
    @graph.expects(:search_users).with("ann", limit: 10).returns([
      { "id" => "1", "displayName" => "Ann", "userType" => "Member", "accountEnabled" => true, "mail" => "ann@contoso.com" },
      { "id" => "2", "displayName" => "Ann Guest", "userType" => "Guest" },
      { "id" => "3", "displayName" => "Ann Old", "accountEnabled" => false }
    ])

    assert_equal [ "1" ], adapter.search_users(query: "ann", limit: 10).map { |record| record["id"] }
  end

  test "lists channels as TEAM_ID|CHANNEL_ID with readable labels" do
    @graph.stubs(:teams).returns([ { "id" => TEAMS_TEAM_ID, "displayName" => "Engineering" } ])
    @graph.stubs(:channels).with(TEAMS_TEAM_ID).returns([
      { "id" => "19:standup@thread.tacv2", "displayName" => "Standup", "membershipType" => "standard" },
      { "id" => "19:secret@thread.tacv2", "displayName" => "Secret", "membershipType" => "private" }
    ])

    records = adapter.list_channels(query: "standup")

    assert_equal [ TEAMS_CHANNEL ], records.map { |record| record["id"] }
    assert_equal "Engineering › Standup", records.first["label"]
    assert_equal [ TEAMS_CHANNEL ], adapter.list_channels(include_private: false).map { |record| record["id"] }
  end

  test "channel members come back as importable profiles" do
    @graph.expects(:channel_members).with(TEAMS_TEAM_ID, "19:standup@thread.tacv2").returns([
      { "userId" => TEAMS_USER_ID.upcase, "displayName" => "Tess Teams" }
    ])
    @graph.expects(:user_time_zone).with(TEAMS_USER_ID).returns("Europe/Paris")

    assert_equal [ { "platform_user_id" => TEAMS_USER_ID, "display_name" => "Tess Teams", "cached_timezone" => "Europe/Paris" } ],
      adapter.channel_member_profiles(TEAMS_CHANNEL)
  end

  test "validates object IDs and channel references" do
    assert adapter.valid_user_id?(TEAMS_USER_ID)
    assert_not adapter.valid_user_id?("U123ABC")
    assert_equal TEAMS_USER_ID, adapter.normalize_user_id(" #{TEAMS_USER_ID.upcase} ")
    assert adapter.valid_channel?(TEAMS_CHANNEL)
    assert_not adapter.valid_channel?("general")
  end

  test "channel references use the stored name" do
    assert_equal "Engineering › Standup", adapter.channel_reference(TEAMS_CHANNEL, name: "Engineering › Standup")
    assert_equal "your team's channel", adapter.channel_reference(TEAMS_CHANNEL)
  end

  test "plain_text strips mentions and HTML" do
    assert_equal "standup status", ChatPlatform.for(:teams).plain_text("<at>Standup Bot</at> standup status")
    assert_equal "Fixed bugs & shipped\nNext: tests", ChatPlatform.for(:teams).plain_text("<p>Fixed <b>bugs</b> &amp; shipped<br>Next: tests</p>")
  end
end

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

  test "post_standup_update shows a compact heading and puts each answer under a colored bar" do
    sent = nil
    @client.expects(:send_message).with { |*args, **options| sent = [ args, options ]; true }.returns({ "channel" => "C1", "ts" => "9.9" })

    message = adapter.post_standup_update("team", display_name: "Ann", standup_name: "Daily", answers: [ { question: "Q1", answer: "A1" }, { question: "Q2", answer: "A2" } ])

    (channel, text, blocks), options = sent
    attachments = options[:attachments]
    assert_equal "9.9", message.id
    assert_equal "team", channel
    # The top-level text is what screen readers and notifications use, so it has everything.
    assert_equal "*Ann* posted an update for *Daily*\n\n*Q1*\nA1\n\n*Q2*\nA2", text
    assert_equal [ "*Ann* posted an update for *Daily*" ], blocks.map { |block| block.dig(:text, :text) }
    assert_equal ChatPlatform::SlackAdapter::ANSWER_COLORS.first(2), attachments.map { |attachment| attachment[:color] }
    assert_equal [ "*Q1*\nA1", "*Q2*\nA2" ], attachments.map { |attachment| attachment[:blocks].first.dig(:text, :text) }
    assert_equal "Q1: A1", attachments.first[:fallback]
  end

  test "post_standup_update splits long answers across blocks" do
    attachments = nil
    @client.expects(:send_message)
      .with { |*_args, **options| attachments = options[:attachments]; true }
      .returns({ "channel" => "C1", "ts" => "9.9" })

    adapter.post_standup_update("team", display_name: "Ann", standup_name: "Daily", answers: [ { question: "Q1", answer: "x" * 7_000 } ])

    texts = attachments.first[:blocks].map { |block| block.dig(:text, :text) }
    assert_equal 3, texts.size
    assert texts.all? { |text| text.length <= ChatPlatform::SlackAdapter::SECTION_TEXT_LIMIT }
    assert_equal "*Q1*\n#{"x" * 7_000}", texts.join
  end

  test "long answers split at line breaks or spaces and never through links or mentions" do
    attachments = nil
    @client.expects(:send_message)
      .with { |*_args, **options| attachments = options[:attachments]; true }
      .returns({ "channel" => "C1", "ts" => "9.9" })
    link = "<https://example.com/tickets/#{"1" * 40}|ticket>"
    answer = "#{"a" * 2_980}#{link} and <@U123ABC> #{"word " * 700}"

    adapter.post_standup_update("team", display_name: "Ann", standup_name: "Daily", answers: [ { question: "Q1", answer: answer } ])

    texts = attachments.first[:blocks].map { |block| block.dig(:text, :text) }
    assert texts.all? { |text| text.length <= ChatPlatform::SlackAdapter::SECTION_TEXT_LIMIT }
    assert texts.all? { |text| text.count("<") == text.count(">") }, "a section split through Slack markup"
    assert texts.any? { |text| text.include?(link) }
    assert texts.drop(1).all? { |text| !text.start_with?(" ", "\n") }
  end

  test "update_standup_update edits the heading and answers in place" do
    @client.expects(:update_message).with do |channel, ts, text, blocks, **options|
      channel == "team" && ts == "9.9" && text == "*Ann* posted an update for *Daily*\n\n*Q1*\nA1" &&
        blocks.map { |block| block.dig(:text, :text) } == [ "*Ann* posted an update for *Daily*" ] &&
        options[:attachments].map { |attachment| attachment[:blocks].first.dig(:text, :text) } == [ "*Q1*\nA1" ]
    end

    adapter.update_standup_update("team", "9.9", display_name: "Ann", standup_name: "Daily", answers: [ { question: "Q1", answer: "A1" } ])
  end

  test "update_standup_update with no answers left says the person skipped and clears the answers" do
    @client.expects(:update_message).with(
      "team", "9.9", "*Ann* skipped *Daily*",
      [ { type: "section", text: { type: "mrkdwn", text: "*Ann* skipped *Daily*" } } ],
      attachments: []
    )

    adapter.update_standup_update("team", "9.9", display_name: "Ann", standup_name: "Daily", answers: [])
  end

  test "send_standup_kickoff splits an oversized intro across sections" do
    @client.stubs(:get_user_info).returns(nil)
    blocks = nil
    @client.expects(:send_message).with { |_user, _text, sent_blocks| blocks = sent_blocks; true }.returns({ "channel" => "D1", "ts" => "1" })

    adapter.send_standup_kickoff("U1", standup_name: "Daily", channel: "team", intro: "word " * 700, question: "Q1", question_count: 1)

    sections = blocks.select { |block| block[:type] == "section" }.map { |block| block.dig(:text, :text) }
    assert_operator sections.size, :>, 2
    assert sections.all? { |text| text.length <= ChatPlatform::SlackAdapter::SECTION_TEXT_LIMIT }
    assert_equal "*Q1*", sections.last
  end

  test "send_standup_kickoff greets generically when the profile lookup fails" do
    @client.stubs(:get_user_info).raises(Faraday::ConnectionFailed, "down")
    blocks = nil
    @client.expects(:send_message).with { |_user, _text, sent_blocks| blocks = sent_blocks; true }.returns({ "channel" => "D1", "ts" => "1" })

    adapter.send_standup_kickoff("U1", standup_name: "Daily", channel: "team", intro: "", question: "Q1", question_count: 1)

    assert_equal "Hi there! 👋 It's time for *Daily* in #team.", blocks.third.dig(:text, :text)
  end

  test "send_standup_kickoff falls back to a friendly greeting without a profile" do
    @client.stubs(:get_user_info).returns(nil)
    blocks = nil
    @client.expects(:send_message).with { |_user, _text, sent_blocks| blocks = sent_blocks; true }.returns({ "channel" => "D1", "ts" => "1" })

    adapter.send_standup_kickoff("U1", standup_name: "Daily", channel: "team", intro: "", question: "Q1", question_count: 1)

    assert_equal "Hi there! 👋 It's time for *Daily* in #team.", blocks.third.dig(:text, :text)
    assert_equal "Starting *Daily* · 1 question · Reply `skip` to pass on one", blocks.first[:elements].first[:text]
  end

  test "channel_mention links channel IDs and falls back to the name" do
    assert_equal "<#C0123ABC>", adapter.channel_mention("C0123ABC", name: "team")
    assert_equal "#team", adapter.channel_mention("team")
  end

  test "send_action renders a section with a button" do
    @client.expects(:send_message).with("D1", "You skipped *Daily*.", [
      {
        type: "section",
        text: { type: "mrkdwn", text: "You skipped *Daily*." },
        accessory: { type: "button", text: { type: "plain_text", text: "Restart" }, action_id: "standup_restart", value: "5" }
      }
    ]).returns({ "channel" => "D1", "ts" => "1" })

    adapter.send_action("D1", "You skipped *Daily*.", button: { text: "Restart", value: 5 }, action_id: "standup_restart")
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
    @client.expects(:list_channels).with(query: "g", limit: 6).returns([ { "id" => "C1" } ])
    @client.expects(:channel_members).with("C1").returns([ "U1" ])
    @client.expects(:auth_test).returns({ "team_id" => "T1" })

    assert_equal [ { "id" => "U1" } ], adapter.search_users(query: "a", limit: 5)
    assert_equal [ { "id" => "C1" } ], adapter.list_channels(query: "g", limit: 6)
    assert_equal [ "U1" ], adapter.channel_member_ids("C1")
    assert_equal "T1", adapter.connection_status["team_id"]
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

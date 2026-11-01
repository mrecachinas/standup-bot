require "test_helper"
require_relative "../support/teams_test_helper"

class TeamsActivityProcessorJobTest < ActiveJob::TestCase
  include TeamsTestHelper

  setup do
    enable_teams!
    @standup = create_teams_standup!
    @sent = []
    sent = @sent
    ChatPlatform::TeamsAdapter.any_instance.stubs(:send_message).with { |target, text| sent << [ target, text ] }.returns(ChatPlatform::MessageRef.new(channel: "a:chat", id: "1"))
    ChatPlatform::TeamsAdapter.any_instance.stubs(:send_direct_message).with { |target, text| sent << [ target, text ] }.returns(ChatPlatform::MessageRef.new(channel: "a:chat", id: "2"))
    ChatPlatform::TeamsAdapter.any_instance.stubs(:post_standup_update).returns(ChatPlatform::MessageRef.new(channel: "19:x;messageid=9", id: "9"))
    ChatPlatform::TeamsAdapter.any_instance.stubs(:user_profile).returns(ChatPlatform::UserProfile.new(id: TEAMS_USER_ID, display_name: "Tess Teams"))
  end

  def activity(text: nil, type: "message", conversation_type: "personal", value: nil, user_id: TEAMS_USER_ID.upcase)
    {
      "type" => type,
      "text" => text,
      "value" => value,
      "serviceUrl" => "https://smba.trafficmanager.net/amer/",
      "channelId" => "msteams",
      "from" => { "id" => "29:abc", "aadObjectId" => user_id },
      "conversation" => { "id" => conversation_type == "personal" ? "a:chat" : "19:chan;messageid=1", "conversationType" => conversation_type, "tenantId" => TEAMS_TENANT_ID }
    }.compact
  end

  def pending_response!
    StandupResponse.create!(standup: @standup, platform_user_id: TEAMS_USER_ID, status: "pending", answers: [], standup_date: Date.current, dm_channel: "a:chat")
  end

  test "remembers the 1:1 conversation from any personal activity" do
    TeamsActivityProcessorJob.perform_now(activity(type: "conversationUpdate"))

    conversation = ChatConversation.find_by!(platform: "teams", platform_user_id: TEAMS_USER_ID)
    assert_equal "a:chat", conversation.conversation_id
    assert_equal "https://smba.trafficmanager.net/amer/", conversation.service_url
  end

  test "records answers and asks the next question in Teams markdown" do
    response = pending_response!

    TeamsActivityProcessorJob.perform_now(activity(text: "<p>Shipped the <b>adapter</b></p>"))

    assert_equal "Shipped the adapter", response.reload.answers.first["answer"]
    assert @sent.any? { |target, text| target == TEAMS_USER_ID && text.include?("**Question 2/2:**") }
  end

  test "finishing a standup posts to the channel and names it" do
    response = pending_response!
    ChatPlatform::TeamsAdapter.any_instance.expects(:post_standup_update)
      .with(TEAMS_CHANNEL, display_name: "Tess Teams", answers: [ { question: "Yesterday?", answer: "A1" }, { question: "Today?", answer: "A2" } ])
      .returns(ChatPlatform::MessageRef.new(channel: "19:x;messageid=9", id: "9"))

    TeamsActivityProcessorJob.perform_now(activity(text: "A1"))
    TeamsActivityProcessorJob.perform_now(activity(text: "A2"))

    assert_equal "completed", response.reload.status
    assert_equal "9", response.platform_message_id
    assert @sent.any? { |_target, text| text.include?("posted to Engineering › Standup") }
  end

  test "standup commands reply in the chat" do
    TeamsActivityProcessorJob.perform_now(activity(text: "standup status"))

    target, text = @sent.last
    assert_equal "a:chat", target
    assert_includes text, "**Standup status:**"
    assert_includes text, "• Teams Standup:"
  end

  test "text that only starts with 'standup' is still an answer" do
    response = pending_response!

    TeamsActivityProcessorJob.perform_now(activity(text: "standup prep and planning"))

    assert_equal "standup prep and planning", response.reload.answers.first["answer"]
  end

  test "DM commands like help work in Teams" do
    TeamsActivityProcessorJob.perform_now(activity(text: "help"))

    assert_includes @sent.last.last, "**Available Commands:**"
  end

  test "card choices run the chosen command" do
    assert_enqueued_with(job: StandupCollectionJob) do
      TeamsActivityProcessorJob.perform_now(activity(value: { "action_id" => "standup_selection", "standup_id" => @standup.id.to_s }))
    end

    assert_includes @sent.last.last, "Generating report for Teams Standup"
  end

  test "mentions in a channel are answered privately" do
    TeamsActivityProcessorJob.perform_now(activity(text: "<at>Standup Bot</at> status", conversation_type: "channel"))

    target, text = @sent.last
    assert_equal TEAMS_USER_ID, target
    assert_includes text, "Standup status"
    assert_not ChatConversation.exists?(platform: "teams", conversation_id: "19:chan;messageid=1")
  end

  test "edits update the latest pending answer" do
    response = pending_response!
    response.update!(answers: [ { "question" => "Yesterday?", "answer" => "old", "timestamp" => Time.current } ])

    TeamsActivityProcessorJob.perform_now(activity(text: "new", type: "messageUpdate"))

    assert_equal "new", response.reload.answers.first["answer"]
  end

  test "doesn't answer Slack standups for a matching user ID" do
    slack_id = standup_participants(:one).platform_user_id
    slack_response = StandupResponse.create!(standup: standups(:daily), platform_user_id: slack_id, status: "pending", answers: [], standup_date: Date.current + 1)

    TeamsActivityProcessorJob.perform_now(activity(text: "hello", user_id: slack_id))

    assert_empty slack_response.reload.answers
  end
end

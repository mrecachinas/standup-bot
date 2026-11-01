require "test_helper"

class StandupCommandHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # A markdown-flavored chat, to check the handler doesn't hard-code Slack syntax.
  class MarkdownChat
    module Formatter
      module_function

      def bold(text) = "**#{text}**"
      def italic(text) = "_#{text}_"
      def code(text) = "`#{text}`"
      def channel_reference(channel) = "the #{channel} channel"
    end

    def formatter = Formatter
    def channel_reference(channel) = Formatter.channel_reference(channel)
  end

  setup do
    @participant = standup_participants(:one)
    @handler = StandupCommandHandler.new(chat: MarkdownChat.new, user_id: @participant.slack_id, base_command: "standup", status_command: nil)
  end

  test "help uses the platform's command name and formatting" do
    text = @handler.run("help").text

    assert_includes text, "**Available `standup` commands:**"
    assert_includes text, "• `standup status` — check today's progress"
    assert_not_includes text, "/standup"
  end

  test "unknown commands fall back to help" do
    assert_match(/\AI don't recognize `dance`\./, @handler.run("dance").text)
  end

  test "status lists each active standup" do
    reply = @handler.run("status")

    assert_not reply.selection?
    assert_includes reply.text, "**Standup status:**"
    assert_includes reply.text, "• #{@participant.standup.name}:"
  end

  test "report with one standup queues the report and names the channel" do
    StandupParticipant.where(slack_id: @participant.slack_id).where.not(id: @participant.id).delete_all

    assert_enqueued_with(job: StandupCollectionJob) do
      reply = @handler.run("report")
      assert_includes reply.text, "It will be posted to the #{@participant.standup.slack_channel} channel shortly."
    end
  end

  test "start with several standups returns a selection" do
    standups(:weekly).standup_participants.create!(slack_id: @participant.slack_id, slack_name: "John Doe", active: true)

    reply = @handler.run("start")

    assert reply.selection?
    assert_equal "standup_start_selection", reply.action_id
    assert_equal [ standups(:daily).id, standups(:weekly).id ].sort, reply.options.map { |option| option[:value] }.sort
  end

  test "selected standups must exist and include the person" do
    assert_equal "I couldn't find that standup.", @handler.report_selected(0).text
    assert_equal "You are not a participant in that standup.", @handler.start_selected(standups(:weekdays).id).text
  end

  test "start_selected queues the DM for a participant" do
    assert_enqueued_with(job: StandupMessageJob) do
      assert_equal "Starting #{standups(:daily).name} now. Check your DMs.", @handler.start_selected(standups(:daily).id).text
    end
  end
end

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

    def key = :slack
    def formatter = Formatter
    def channel_reference(channel, name: nil) = Formatter.channel_reference(name.presence || channel)
    def channel_mention(channel, name: nil) = channel_reference(channel, name: name)
  end

  setup do
    @participant = standup_participants(:one)
    @handler = StandupCommandHandler.new(chat: MarkdownChat.new, user_id: @participant.platform_user_id, base_command: "standup", status_command: nil)
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
    StandupParticipant.where(platform_user_id: @participant.platform_user_id).where.not(id: @participant.id).delete_all

    assert_enqueued_with(job: StandupCollectionJob) do
      reply = @handler.run("report")
      assert_includes reply.text, "It will be posted to the #{@participant.standup.platform_channel} channel shortly."
    end
  end

  test "start with several standups returns a selection" do
    standups(:weekly).standup_participants.create!(platform_user_id: @participant.platform_user_id, display_name: "John Doe", active: true)

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
      assert_equal "Starting **#{standups(:daily).name}** now. Check your DMs.", @handler.start_selected(standups(:daily).id).text
    end
  end

  test "direct_message recognizes each keyword, ignoring case and whitespace" do
    handler = StandupCommandHandler.new(chat: MarkdownChat.new, user_id: "UNOBODY")

    [ "help", "report", "skip", "cancel", "away", "away 3", "back", "  HELP  " ].each do |text|
      assert_kind_of ChatPlatform::Reply, handler.direct_message(text), "expected #{text.inspect} to be a command"
    end
  end

  test "direct_message returns nil for anything else, so it's treated as an answer" do
    [ "This is not a command", "helpful", "", "   ", nil ].each do |text|
      assert_nil @handler.direct_message(text), "expected #{text.inspect} not to be a command"
    end
  end

  test "direct_message help lists the DM keywords" do
    text = @handler.direct_message("help").text

    assert_includes text, "**Available Commands:**"
    assert_includes text, "• `away [days]`"
  end

  test "direct_message report queues the report for the participant's local date" do
    participant = StandupParticipant.create!(
      standup: standups(:daily), platform_user_id: "U12345678", display_name: "Report User",
      active: true, cached_timezone: "UTC", cached_timezone_updated_at: Time.current
    )
    handler = StandupCommandHandler.new(chat: MarkdownChat.new, user_id: participant.platform_user_id)

    StandupCollectionJob.expects(:perform_later).with(standups(:daily).id, participant.standup_date_for(Time.current).iso8601, "Etc/UTC")

    assert_match(/\AGenerating report for/, handler.direct_message("report").text)
  end

  test "direct_message skip and cancel need a pending standup" do
    handler = StandupCommandHandler.new(chat: MarkdownChat.new, user_id: "UNOBODY")

    assert_equal "You don't have an active standup to skip questions for.", handler.direct_message("skip").text
    assert_equal "You don't have an active standup to cancel.", handler.direct_message("cancel").text
  end

  test "direct_message cancel cancels the latest pending response" do
    response = StandupResponse.create!(standup: @participant.standup, platform_user_id: @participant.platform_user_id, status: "pending", answers: [], standup_date: Date.current)

    reply = @handler.direct_message("cancel")

    assert_equal "You cancelled **#{@participant.standup.name}**. You can restart it anytime.", reply.text
    assert_equal({ text: "Restart", value: @participant.standup.id }, reply.button)
    assert_equal StandupCommandHandler::RESTART_ACTION_ID, reply.action_id
    assert_equal "cancelled", response.reload.status
  end

  test "direct_message skip moves on without its own reply" do
    response = StandupResponse.create!(standup: @participant.standup, platform_user_id: @participant.platform_user_id, status: "pending", answers: [], standup_date: Date.current)
    StandupResponseService.expects(:skip_question).with(response)

    assert @handler.direct_message("skip").none?
  end

  test "skip offers to restart a single skipped standup" do
    standup = @participant.standup
    @participant.update!(cached_timezone: "UTC", cached_timezone_updated_at: Time.current)
    StandupResponse.create!(standup: standup, platform_user_id: @participant.platform_user_id, status: "pending", answers: [], standup_date: @participant.standup_date_for(Time.current))
    StandupResponseService.stubs(:skip_remaining_questions)

    reply = @handler.run("skip")

    assert_equal "You skipped **#{standup.name}**. You can restart it anytime.", reply.text
    assert_equal({ text: "Restart", value: standup.id }, reply.button)
  end

  test "restart queues a fresh run for the day" do
    standup = standups(:daily)

    assert_enqueued_with(job: StandupMessageJob, args: [ @participant.platform_user_id, standup.id, @participant.standup_date_for(Time.current).iso8601, { restart: true } ]) do
      assert_equal "Restarting **#{standup.name}**…", @handler.restart(standup.id).text
    end
  end

  test "direct_message away pauses active standups and schedules the return" do
    Timecop.freeze(Time.zone.local(2025, 4, 7, 9)) do
      assert_enqueued_with(job: ParticipantReactivationJob) do
        assert_match(/until Thursday, April 10/, @handler.direct_message("away 3").text)
      end
    end

    assert_not @participant.reload.active?
    assert_equal Date.new(2025, 4, 10), @participant.vacation_until
  end

  test "direct_message back ends time away that was set on the web" do
    @participant.update!(active: true, vacation_until: Date.current + 3)

    assert_match(/Welcome back/, @handler.direct_message("back").text)
    assert_nil @participant.reload.vacation_until
    assert @participant.active?
  end
end

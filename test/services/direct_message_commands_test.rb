require "test_helper"

class DirectMessageCommandsTest < ActiveSupport::TestCase
  setup do
    @slack_client = mock("SlackClient")
    SlackClient.stubs(:instance).returns(@slack_client)
    @commands = DirectMessageCommands.new(ChatPlatform.for(:slack))
    @slack_id = "U12345678"
    @channel = "D87654321"
  end

  test "parse recognizes each command" do
    {
      "help" => :help,
      "report" => :report,
      "skip" => :skip,
      "cancel" => :cancel,
      "away" => :away,
      "back" => :back
    }.each do |text, command|
      assert_equal command, @commands.parse(text)&.fetch(:command), "expected #{text.inspect} to parse as #{command}"
    end
  end

  test "parse captures optional away days" do
    assert_nil @commands.parse("away")[:match][1]
    assert_equal "10", @commands.parse("away 10")[:match][1]
  end

  test "parse is case insensitive and trims whitespace" do
    assert_equal :help, @commands.parse("HELP")[:command]
    assert_equal :help, @commands.parse("  help  ")[:command]
  end

  test "parse returns nil for non-command, nil, or blank text" do
    assert_nil @commands.parse("This is not a command")
    assert_nil @commands.parse(nil)
    assert_nil @commands.parse("   ")
  end

  test "process should handle help command" do
    @slack_client.expects(:send_message).with(@channel, is_a(String))

    command_info = { command: :help, match: "help".match(/^help$/i) }
    @commands.process(command_info, @slack_id, @channel)
  end

  test "process should handle unknown command" do
    @slack_client.expects(:send_message).with(@channel, is_a(String))

    command_info = { command: :unknown_command, match: nil }
    @commands.process(command_info, @slack_id, @channel)
  end

  test "process should generate report for participant timezone date" do
    standup = standups(:daily)
    participant = StandupParticipant.create!(
      standup: standup,
      slack_id: @slack_id,
      slack_name: "Report User",
      active: true,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )

    StandupCollectionJob.expects(:perform_later).with(
      standup.id,
      participant.standup_date_for(Time.current).iso8601,
      "Etc/UTC"
    )
    @slack_client.expects(:send_message).with(@channel, includes("Generating report"))

    command_info = { command: :report, match: "report".match(/^report$/i) }
    @commands.process(command_info, @slack_id, @channel)
  end

  test "process should handle skip command when no standup is active" do
    @slack_client.expects(:send_message).with(@channel, "You don't have an active standup to skip questions for.")
    StandupResponse.expects(:authorized_for_slack_user).with(@slack_id).returns(StandupResponse.none)

    command_info = { command: :skip, match: "skip".match(/^skip$/i) }
    @commands.process(command_info, @slack_id, @channel)
  end

  test "process should handle cancel command when no standup is active" do
    @slack_client.expects(:send_message).with(@channel, "You don't have an active standup to cancel.")
    StandupResponse.expects(:authorized_for_slack_user).with(@slack_id).returns(StandupResponse.none)

    command_info = { command: :cancel, match: "cancel".match(/^cancel$/i) }
    @commands.process(command_info, @slack_id, @channel)
  end

  test "back ends time away that was set on the web" do
    participant = standup_participants(:one)
    participant.update!(active: true, vacation_until: Date.current + 3)
    @slack_client.expects(:send_message).with(@channel, regexp_matches(/Welcome back/))

    @commands.process(@commands.parse("back"), participant.slack_id, @channel)

    assert_nil participant.reload.vacation_until
    assert participant.active?
  end
end

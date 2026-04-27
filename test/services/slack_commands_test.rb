require "test_helper"

class SlackCommandsTest < ActiveSupport::TestCase
  setup do
    @slack_client = mock("SlackClient")
    @commands = SlackCommands.new(@slack_client)
    @slack_id = "U12345678"
    @channel = "D87654321"
  end

  test "parse should recognize help command" do
    result = @commands.parse("help")

    assert_equal :help, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should recognize report command" do
    result = @commands.parse("report")

    assert_equal :report, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should recognize skip command" do
    result = @commands.parse("skip")

    assert_equal :skip, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should recognize cancel command" do
    result = @commands.parse("cancel")

    assert_equal :cancel, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should recognize away command without days" do
    result = @commands.parse("away")

    assert_equal :away, result[:command]
    assert_not_nil result[:match]
    assert_nil result[:match][1] # No days specified
  end

  test "parse should recognize away command with days" do
    result = @commands.parse("away 10")

    assert_equal :away, result[:command]
    assert_not_nil result[:match]
    assert_equal "10", result[:match][1] # Days specified
  end

  test "parse should recognize back command" do
    result = @commands.parse("back")

    assert_equal :back, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should be case insensitive" do
    result = @commands.parse("HELP")

    assert_equal :help, result[:command]
    assert_not_nil result[:match]
  end

  test "parse should return nil for non-command text" do
    result = @commands.parse("This is not a command")

    assert_nil result
  end

  test "parse should return nil for nil text" do
    assert_nil @commands.parse(nil)
  end

  test "parse should return nil for nil or blank text" do
    assert_nil @commands.parse(nil)
    assert_nil @commands.parse("   ")
  end

  test "parse should trim command text" do
    result = @commands.parse("  help  ")

    assert_equal :help, result[:command]
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
end

require "test_helper"

module Instrumentation
  class SubscribersTest < ActiveSupport::TestCase
    setup do
      @output = StringIO.new
      @logger = ActiveSupport::Logger.new(@output)
      @logger.formatter = JsonLogFormatter.new
    end

    test "the log subscriber logs app events" do
      LogSubscriber.new(logger: @logger).emit(name: "standup.sent", payload: { standup_id: 1 }, tags: {})

      line = JSON.parse(@output.string)
      assert_equal "standup.sent", line["event"]
      assert_equal({ "standup_id" => 1 }, line["payload"])
    end

    test "the log subscriber skips framework events" do
      LogSubscriber.new(logger: @logger).emit(name: "action_controller.request_completed", payload: { status: 200 }, tags: {})

      assert_empty @output.string
    end

    test "the error log subscriber logs the error with filtered context" do
      error = build_error(RuntimeError.new("Slack is down"))

      ErrorLogSubscriber.new(logger: @logger).report(
        error, handled: true, severity: :warning, source: "slack_sign_in",
        context: { user_id: 3, token: "xoxb-secret", job: StandupMessageJob.new }
      )

      line = JSON.parse(@output.string)
      assert_equal "WARN", line["level"]
      assert_equal "error.reported", line["event"]
      assert_equal "RuntimeError", line["error_class"]
      assert_equal "Slack is down", line["error_message"]
      assert_equal true, line["handled"]
      assert_equal "slack_sign_in", line["source"]
      assert_equal 3, line.dig("context", "user_id")
      assert_equal "[FILTERED]", line.dig("context", "token")
      assert_match(/\AStandupMessageJob#/, line.dig("context", "job"))
      assert line["backtrace"].any?
    end

    test "unhandled errors are logged at error level" do
      ErrorLogSubscriber.new(logger: @logger).report(build_error(RuntimeError.new("boom")), handled: false, severity: :error, context: {}, source: "application.active_job")

      assert_equal "ERROR", JSON.parse(@output.string)["level"]
    end

    test "install! subscribes the log backends, and StatsD only when configured" do
      events = ActiveSupport::EventReporter.new
      errors = ActiveSupport::ErrorReporter.new

      Instrumentation.install!(event_reporter: events, error_reporter: errors, env: {})
      assert_equal [ LogSubscriber ], events.subscribers.map { |entry| entry[:subscriber].class }

      events = ActiveSupport::EventReporter.new
      errors = ActiveSupport::ErrorReporter.new
      Instrumentation.install!(event_reporter: events, error_reporter: errors, env: { "STATSD_ADDR" => "127.0.0.1:8125" })
      assert_equal [ LogSubscriber, StatsdSubscriber ], events.subscribers.map { |entry| entry[:subscriber].class }
    end

    test "Rails.error reaches the installed error log subscriber" do
      log_output = StringIO.new
      logger = ActiveSupport::Logger.new(log_output)
      logger.formatter = JsonLogFormatter.new
      Rails.stubs(:logger).returns(logger)

      Rails.error.report(RuntimeError.new("reported"), source: "test")

      assert_includes log_output.string, "\"error_message\":\"reported\""
    end

    private

    def build_error(error)
      raise error
    rescue => raised
      raised
    end
  end
end

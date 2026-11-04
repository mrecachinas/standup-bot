require "test_helper"

module Instrumentation
  class JsonLogFormatterTest < ActiveSupport::TestCase
    setup do
      @output = StringIO.new
      @logger = ActiveSupport::TaggedLogging.new(
        ActiveSupport::Logger.new(@output).tap { |logger| logger.formatter = JsonLogFormatter.new }
      )
    end

    test "writes strings as JSON lines with time and level" do
      @logger.warn("Slack closed the connection")

      line = last_line
      assert_equal "WARN", line["level"]
      assert_equal "Slack closed the connection", line["message"]
      assert Time.iso8601(line["time"])
    end

    test "merges hash messages" do
      @logger.info(method: "GET", path: "/api/standups", status: 200)

      line = last_line
      assert_equal "GET", line["method"]
      assert_equal 200, line["status"]
      refute line.key?("message")
    end

    test "adds the instrumentation context" do
      Instrumentation.set_context(request_id: "req-1", user_id: 7)

      @logger.info("hello")

      assert_equal "req-1", last_line["request_id"]
      assert_equal 7, last_line["user_id"]
    end

    test "keeps tags as a list instead of prefixing the message" do
      @logger.tagged("ActiveJob", "StandupMessageJob") { @logger.info("Performing") }

      assert_equal [ "ActiveJob", "StandupMessageJob" ], last_line["tags"]
      assert_equal "Performing", last_line["message"]
    end

    test "survives invalid encodings" do
      @logger.info("bad byte \xff".b)

      assert_equal "bad byte \uFFFD", last_line["message"]
    end

    private

    def last_line
      JSON.parse(@output.string.lines.last)
    end
  end
end

require "test_helper"

module Instrumentation
  class StatsdSubscriberTest < ActiveSupport::TestCase
    class FakeSocket
      attr_reader :sent, :connected_to

      def initialize
        @sent = []
      end

      def connect(host, port)
        @connected_to = [ host, port ]
      end

      def send(line, _flags)
        @sent << line
      end

      def close; end
    end

    setup do
      @socket = FakeSocket.new
      @subscriber = StatsdSubscriber.new(address: "statsd.internal:9125", socket_factory: -> { @socket })
    end

    test "counts app events with only low-cardinality tags" do
      emit("standup.reminder_failed", standup_id: 4, response_id: 9, error_class: "Slack::Web::Api::Errors::ChannelNotFound")

      assert_equal [ "statsd.internal", 9125 ], @socket.connected_to
      assert_equal [ "standup_bot.standup.reminder_failed:1|c|#error_class:Slack::Web::Api::Errors::ChannelNotFound" ], @socket.sent
    end

    test "sends measured events as timings" do
      emit("slack.api_request", operation: "send_message", outcome: "success", duration_ms: 12.345)

      assert_equal [ "standup_bot.slack.api_request:12.35|ms|#operation:send_message,outcome:success" ], @socket.sent
    end

    test "times requests" do
      emit("action_controller.request_completed", controller: "Api::StandupsController", action: "index", status: 200, duration_ms: 31.2, params: { "id" => "1" })

      assert_equal [ "standup_bot.http.request:31.2|ms|#controller:Api::StandupsController,action:index,status:200" ], @socket.sent
    end

    test "times jobs with their outcome" do
      emit("active_job.completed", job_class: "StandupMessageJob", job_id: "abc", queue: "default", duration: 5.0)
      emit("active_job.completed", job_class: "StandupMessageJob", job_id: "def", queue: "default", duration: 7.0, exception_class: "RuntimeError")

      assert_equal [
        "standup_bot.job.perform:5.0|ms|#job_class:StandupMessageJob,queue:default,outcome:success",
        "standup_bot.job.perform:7.0|ms|#job_class:StandupMessageJob,queue:default,outcome:error"
      ], @socket.sent
    end

    test "counts job retries" do
      emit("active_job.retry_scheduled", job_class: "StandupPromptJob", job_id: "abc", exception_class: "Net::ReadTimeout")

      assert_equal [ "standup_bot.job.retry_scheduled:1|c|#job_class:StandupPromptJob,error_class:Net::ReadTimeout" ], @socket.sent
    end

    test "ignores other framework events" do
      emit("action_controller.request_started", controller: "HealthController", action: "show")

      assert_empty @socket.sent
    end

    test "counts reported errors" do
      @subscriber.report(RuntimeError.new("boom"), handled: true, severity: :warning, context: { user_id: 1 }, source: "slack_sign_in")

      assert_equal [ "standup_bot.error:1|c|#error_class:RuntimeError,handled:true,severity:warning,source:slack_sign_in" ], @socket.sent
    end

    test "sanitizes tag values and metric names" do
      emit("odd event|name", operation: "a,b|c#d e")

      assert_equal [ "standup_bot.odd_event_name:1|c|#operation:a_b_c_d_e" ], @socket.sent
    end

    test "never raises when the agent can't be reached" do
      @socket.define_singleton_method(:send) { |*| raise Errno::ECONNREFUSED }

      assert_nothing_raised { emit("standup.sent", standup_id: 1) }
    end

    private

    def emit(name, payload)
      @subscriber.emit(name: name, payload: payload, tags: {}, context: {})
    end
  end
end

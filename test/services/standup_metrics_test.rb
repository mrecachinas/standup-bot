require "test_helper"

class StandupMetricsTest < ActiveSupport::TestCase
  class RecordingSubscriber
    attr_reader :events

    def initialize
      @events = []
    end

    def emit(event)
      @events << event
    end
  end

  setup do
    @subscriber = RecordingSubscriber.new
    Rails.event.subscribe(@subscriber)
  end

  teardown { Rails.event.unsubscribe(@subscriber) }

  test "track reports the event through Rails.event and caches last seen" do
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(cache)

    Timecop.freeze(Time.zone.local(2026, 6, 9, 13, 20, 0)) do
      StandupMetrics.track("standup.sent", standup_id: 42, platform_user_id: nil)
      assert_equal Time.current.iso8601, StandupMetrics.last_seen("standup.sent")
    end

    event = @subscriber.events.sole
    assert_equal "standup.sent", event[:name]
    assert_equal({ standup_id: 42 }, event[:payload])
    assert_equal __FILE__, event.dig(:source_location, :filepath)
  end

  test "tags named like filtered parameters are masked" do
    StandupMetrics.track("scheduling.completed", dms_scheduled: 7, messages_scheduled: 7)

    assert_equal({ dms_scheduled: 7, messages_scheduled: "[FILTERED]" }, @subscriber.events.sole[:payload])
  end

  test "job summaries keep their counts" do
    StandupMetrics.stubs(:cache_last_seen)
    SchedulingJob.perform_now
    DataCleanupJob.perform_now

    scheduling = @subscriber.events.find { |event| event[:name] == "scheduling.completed" }[:payload]
    cleanup = @subscriber.events.find { |event| event[:name] == "data_cleanup.completed" }[:payload]
    assert_kind_of Integer, scheduling[:dms_scheduled]
    assert_kind_of Integer, cleanup[:processed_chat_records_deleted]
    assert_not_includes (scheduling.values + cleanup.values), "[FILTERED]"
  end

  test "track writes last seen timestamps with a seven day expiration" do
    cache = mock("cache")
    Rails.stubs(:cache).returns(cache)

    Timecop.freeze(Time.zone.local(2026, 6, 9, 13, 20, 0)) do
      cache.expects(:write).with("standup_metrics:slack.rate_limited:last_seen", Time.current.iso8601, expires_in: 7.days)

      StandupMetrics.track("slack.rate_limited", retry_after: 30)
    end
  end

  test "track logs the event as structured data" do
    log_output = StringIO.new
    logger = ActiveSupport::Logger.new(log_output)
    logger.formatter = Instrumentation::JsonLogFormatter.new
    Rails.stubs(:logger).returns(logger)

    StandupMetrics.track("standup.sent", standup_id: 42)

    line = JSON.parse(log_output.string.lines.last)
    assert_equal "standup.sent", line["event"]
    assert_equal({ "standup_id" => 42 }, line["payload"])
  end

  test "measure reports the duration and outcome" do
    result = StandupMetrics.measure("slack.api_request", operation: "send_message") { :sent }

    assert_equal :sent, result
    payload = @subscriber.events.sole[:payload]
    assert_equal "send_message", payload[:operation]
    assert_equal "success", payload[:outcome]
    assert_kind_of Float, payload[:duration_ms]
  end

  test "measure reports failures with the error class and re-raises" do
    assert_raises(Faraday::TimeoutError) do
      StandupMetrics.measure("slack.api_request", operation: "send_message") { raise Faraday::TimeoutError }
    end

    payload = @subscriber.events.sole[:payload]
    assert_equal "error", payload[:outcome]
    assert_equal "Faraday::TimeoutError", payload[:error_class]
  end

  test "measure doesn't record last seen" do
    cache = mock("cache")
    cache.expects(:write).never
    Rails.stubs(:cache).returns(cache)

    StandupMetrics.measure("slack.api_request") { nil }
  end

  test "last_seen reads the metric cache key" do
    cache = mock("cache")
    Rails.stubs(:cache).returns(cache)

    cache.expects(:read).with("standup_metrics:standup.completed:last_seen").returns("2026-06-09T13:20:00Z")

    assert_equal "2026-06-09T13:20:00Z", StandupMetrics.last_seen("standup.completed")
  end
end

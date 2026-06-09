require "test_helper"

class StandupMetricsTest < ActiveSupport::TestCase
  test "track logs structured JSON and caches last seen timestamp" do
    cache = ActiveSupport::Cache::MemoryStore.new
    log_output = StringIO.new
    logger = Logger.new(log_output)
    logger.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
    expected_timestamp = nil

    Rails.stubs(:cache).returns(cache)
    Rails.stubs(:logger).returns(logger)

    Timecop.freeze(Time.zone.local(2026, 6, 9, 13, 20, 0)) do
      expected_timestamp = Time.current.iso8601
      StandupMetrics.track("standup.sent", standup_id: 42, slack_id: nil)
    end

    payload = JSON.parse(log_output.string)

    assert_equal "standup.sent", payload["event"]
    assert_equal({ "standup_id" => 42 }, payload["tags"])
    assert_equal expected_timestamp, payload["timestamp"]
    assert_equal expected_timestamp, StandupMetrics.last_seen("standup.sent")
  end

  test "track writes last seen timestamps with a seven day expiration" do
    cache = mock("cache")
    logger = mock("logger")
    timestamp = nil

    Rails.stubs(:cache).returns(cache)
    Rails.stubs(:logger).returns(logger)

    Timecop.freeze(Time.zone.local(2026, 6, 9, 13, 20, 0)) do
      timestamp = Time.current.iso8601
      logger.expects(:info).with({
        event: "slack.rate_limited",
        tags: { retry_after: 30 },
        timestamp: timestamp
      }.to_json)
      cache.expects(:write).with(
        "standup_metrics:slack.rate_limited:last_seen",
        timestamp,
        expires_in: 7.days
      )

      StandupMetrics.track("slack.rate_limited", retry_after: 30)
    end
  end

  test "last_seen reads the metric cache key" do
    cache = mock("cache")
    Rails.stubs(:cache).returns(cache)

    cache.expects(:read).with("standup_metrics:standup.completed:last_seen").returns("2026-06-09T13:20:00Z")

    assert_equal "2026-06-09T13:20:00Z", StandupMetrics.last_seen("standup.completed")
  end
end

class StandupMetrics
  class << self
    # Reports an app event through Rails.event, where Instrumentation's
    # subscribers log it and count it (see lib/instrumentation.rb). Keep tags to
    # IDs, counts, and error classes: never message text or error messages.
    # Rails masks any tag whose key contains a filter_parameters word (such as
    # "message" or "token"), so name counts accordingly (dms_scheduled, not
    # messages_scheduled).
    def track(event, tags = {})
      ActiveSupport.event_reporter.notify(event, tags.compact, caller_depth: 2)
      cache_last_seen(event)
    end

    # Times the block and tracks the event with its duration_ms and outcome
    # ("success" or "error", with the error_class), which StatsD records as a
    # timing. Errors are re-raised. The block can set tags[:outcome] to report
    # a failure it doesn't raise, such as an HTTP error response. Unlike track,
    # it doesn't record last_seen, since it wraps frequent calls such as each
    # chat API request.
    def measure(event, tags = {})
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = {}
      yield
    rescue Exception => error # rubocop:disable Lint/RescueException
      outcome = { outcome: "error", error_class: error.class.name }
      raise
    ensure
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      ActiveSupport.event_reporter.notify(event, { outcome: "success" }.merge(tags.compact, outcome, duration_ms: duration_ms), caller_depth: 2)
    end

    def last_seen(event)
      Rails.cache.read(cache_key(event))
    rescue StandardError
      nil
    end

    private

    def cache_last_seen(event)
      Rails.cache.write(cache_key(event), Time.current.iso8601, expires_in: 7.days)
    rescue StandardError
      nil
    end

    def cache_key(event)
      "standup_metrics:#{event}:last_seen"
    end
  end
end

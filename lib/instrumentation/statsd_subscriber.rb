require "socket"

module Instrumentation
  # Sends counters and timings to a StatsD agent over UDP, with DogStatsD tags
  # (Datadog's agent and most StatsD servers accept them):
  #
  # * standup_bot.<event> counts each app event (standup.sent, slack.rate_limited, …).
  #   Events with a duration_ms (StandupMetrics.measure) are sent as timings.
  # * standup_bot.http.request times each request, by controller, action, and status.
  # * standup_bot.job.perform times each job run, by job class and outcome;
  #   job.retry_scheduled, job.retry_stopped, and job.discarded count retries.
  # * standup_bot.error counts reported errors, by class and whether they were handled.
  #
  # Only low-cardinality payload keys become tags (TAG_KEYS), so IDs, channels,
  # and messages never do. Sending is fire-and-forget: a missing agent or a
  # network error never affects the app.
  class StatsdSubscriber
    DEFAULT_PREFIX = "standup_bot".freeze
    TAG_KEYS = %i[
      action blocks controller error_class handled host job_class method operation outcome
      platform queue severity source status
    ].freeze
    JOB_COUNTERS = {
      "active_job.retry_scheduled" => "job.retry_scheduled",
      "active_job.retry_stopped" => "job.retry_stopped",
      "active_job.discarded" => "job.discarded"
    }.freeze

    def initialize(address:, prefix: DEFAULT_PREFIX, socket_factory: -> { UDPSocket.new })
      host, port = address.to_s.split(":", 2)
      @host = host.presence || "127.0.0.1"
      @port = (port.presence || 8125).to_i
      @prefix = prefix.presence
      @socket_factory = socket_factory
      @mutex = Mutex.new
    end

    def emit(event)
      name = event[:name].to_s
      payload = event[:payload].is_a?(Hash) ? event[:payload] : {}

      case name
      when "action_controller.request_completed"
        timing("http.request", payload[:duration_ms], payload.slice(:controller, :action, :status))
      when "active_job.completed"
        outcome = payload[:exception_class] ? "error" : "success"
        timing("job.perform", payload[:duration], job_class: payload[:job_class], queue: payload[:queue], outcome: outcome)
      when *JOB_COUNTERS.keys
        increment(JOB_COUNTERS[name], job_class: payload[:job_class], error_class: payload[:exception_class])
      else
        return if Instrumentation.framework_event?(name)

        if payload.key?(:duration_ms)
          timing(name, payload[:duration_ms], tags_for(payload))
        else
          increment(name, tags_for(payload))
        end
      end
    end

    def report(error, handled:, severity:, context:, source:)
      increment("error", error_class: error.class.name, handled: handled, severity: severity, source: source)
    end

    def increment(name, tags = {})
      send_metric(name, 1, "c", tags)
    end

    def timing(name, milliseconds, tags = {})
      return if milliseconds.nil?

      send_metric(name, milliseconds.to_f.round(2), "ms", tags)
    end

    private

    def tags_for(payload)
      payload.slice(*TAG_KEYS)
    end

    def send_metric(name, value, type, tags)
      line = +"#{metric_name(name)}:#{value}|#{type}"
      tag_string = format_tags(tags)
      line << "|##{tag_string}" if tag_string.present?
      socket.send(line, 0)
    rescue StandardError
      reset_socket
      nil
    end

    def metric_name(name)
      [ @prefix, name ].compact.join(".").gsub(/[^A-Za-z0-9_.\-]/, "_")
    end

    def format_tags(tags)
      tags.filter_map do |key, value|
        next if value.nil? || value == ""

        "#{sanitize(key)}:#{sanitize(value)}"
      end.join(",")
    end

    def sanitize(value)
      value.to_s.gsub(/[,|#\s]/, "_")
    end

    # One connected socket per process, so a forked worker doesn't share its
    # parent's, and the agent's address is resolved once.
    def socket
      @mutex.synchronize do
        if @socket.nil? || @socket_pid != Process.pid
          @socket = @socket_factory.call.tap { |socket| socket.connect(@host, @port) }
          @socket_pid = Process.pid
        end
        @socket
      end
    end

    def reset_socket
      @mutex.synchronize do
        @socket&.close rescue nil
        @socket = nil
      end
    end
  end
end

module SlackSocketMode
  # Notes in the shared cache when some client last had a working connection.
  # A client connecting after a gap that no connection covered (every client
  # was down for longer than Slack keeps redelivering events) queues
  # SlackDmBackfillJob to pick up replies sent meanwhile. Also keeps a ready
  # file fresh while connected, for Kubernetes readiness probes
  # (SLACK_SOCKET_MODE_READY_FILE).
  class Presence
    KEY = "slack_socket_mode/alive_at".freeze
    BEAT_INTERVAL = 15
    # Slack redelivers unacked events for about 5 minutes, but a gap that long
    # can't be told apart from a normal one by then, so check after 2.
    OUTAGE_AFTER = 2.minutes

    def initialize(cache: Rails.cache, ready_file: ENV["SLACK_SOCKET_MODE_READY_FILE"].presence, on_outage: -> { SlackDmBackfillJob.perform_later }, logger: Rails.logger)
      @cache = cache
      @ready_file = ready_file
      @on_outage = on_outage
      @logger = logger
      @last_beat = nil
    end

    # Slack said hello.
    def connected!
      last_alive = @cache.read(KEY)
      if last_alive.nil? || last_alive < OUTAGE_AFTER.ago
        @logger.info "No Socket Mode connection since #{last_alive || 'before this cache'}; backfilling missed DMs"
        @on_outage.call
      end
      @last_beat = nil
      beat!
    end

    # Called while connected; writes at most every BEAT_INTERVAL seconds.
    def beat!
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if @last_beat && now - @last_beat < BEAT_INTERVAL

      @last_beat = now
      @cache.write(KEY, Time.current)
      FileUtils.touch(@ready_file) if @ready_file
    end

    def disconnected!
      @last_beat = nil
      FileUtils.rm_f(@ready_file) if @ready_file
    end
  end
end

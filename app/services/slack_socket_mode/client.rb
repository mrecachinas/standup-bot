module SlackSocketMode
  # Keeps a Socket Mode connection to Slack open and hands each envelope to
  # the Dispatcher. Slack refreshes connections every few hours by sending a
  # "disconnect" message, so reconnecting is routine, not an error.
  #
  # Run it with bin/slack-socket-mode, or inside Puma with
  # SLACK_SOCKET_MODE_IN_PUMA=1. Slack allows up to 10 connections per app and
  # sends each envelope to only one of them, so running several is safe.
  class Client
    RECONNECT_DELAYS = [ 1, 2, 5, 10, 30, 60 ].freeze
    READ_TIMEOUT = 1
    PING_AFTER_IDLE = 30
    PING_INTERVAL = 10
    DEAD_AFTER_IDLE = 60
    CONNECTED_METRIC = "slack.socket_connected".freeze

    def initialize(
      app_token: SlackConfig.app_token,
      dispatcher: Dispatcher.new,
      logger: Rails.logger,
      executor: Rails.application.executor,
      web_client: nil,
      # Fully qualified: in Puma, this client outlives development code
      # reloads, and a relative lookup would hit the unloaded constant.
      connection_factory: ->(url) { ::SlackSocketMode::Connection.new(url) },
      presence: ::SlackSocketMode::Presence.new
    )
      @app_token = app_token
      @dispatcher = dispatcher
      @logger = logger
      @executor = executor
      @web_client = web_client
      @connection_factory = connection_factory
      @presence = presence
      @stopped = false
    end

    def run
      raise ArgumentError, "Set SLACK_APP_TOKEN (an xapp- app-level token) to use Slack Socket Mode" if @app_token.blank?

      @logger.info "Starting Slack Socket Mode client"
      failures = 0
      until stopped?
        begin
          failures = session ? 0 : failures + 1
        rescue StandardError => error
          failures += 1
          @logger.error "Slack Socket Mode connection failed: #{error.class}: #{error.message}"
        end

        wait(RECONNECT_DELAYS[[ failures - 1, RECONNECT_DELAYS.size - 1 ].min]) if failures.positive?
      end
      @logger.info "Stopped Slack Socket Mode client"
    end

    def stop
      @stopped = true
    end

    def stopped?
      @stopped
    end

    private

    # Returns whether Slack said hello, i.e. the connection was healthy.
    def session
      @connected = false
      @last_ping_at = nil
      connection = @connection_factory.call(connection_url)
      connection.open
      listen(connection)
      @connected
    ensure
      connection&.close
      @presence.disconnected!
    end

    def connection_url
      response = web_client.apps_connections_open
      response["url"].presence || raise(::SlackSocketMode::Connection::Error, "Slack didn't return a Socket Mode URL")
    end

    def listen(connection)
      until stopped?
        connection.read(timeout: READ_TIMEOUT).each do |message|
          return if handle(connection, message) == :reconnect
        end

        if connection.closed?
          @logger.warn "Slack closed the Socket Mode connection; reconnecting"
          return
        end

        @executor.wrap { @presence.beat! } if @connected

        return if check_idle(connection) == :dead
      end
    end

    def handle(connection, message)
      data = JSON.parse(message)
      return unless data.is_a?(Hash)

      case data["type"]
      when "hello"
        @connected = true
        StandupMetrics.track(CONNECTED_METRIC, connections: data["num_connections"])
        @logger.info "Slack Socket Mode connected (#{data['num_connections'] || 1} connection(s) open)"
        @executor.wrap { @presence.connected! }
      when "disconnect"
        disconnect(data["reason"])
      else
        dispatch(connection, data) if data["envelope_id"].present?
      end
    rescue JSON::ParserError
      @logger.warn "Ignoring malformed Slack Socket Mode message"
    rescue StandardError => error
      @logger.error "Slack Socket Mode envelope type=#{data['type']} failed: #{error.class}: #{error.message}"
    end

    def dispatch(connection, envelope)
      @executor.wrap do
        @dispatcher.call(envelope) { |ack| connection.send_text(ack.to_json) }
      end
    end

    def disconnect(reason)
      if reason == "link_disabled"
        @connected = false
        @logger.error "Slack turned off Socket Mode for this app. Enable it under Settings > Socket Mode, or set SLACK_CONNECTION_MODE=http."
      else
        @logger.info "Slack requested a Socket Mode reconnect (reason=#{reason})"
      end
      :reconnect
    end

    def check_idle(connection)
      idle = connection.idle_seconds
      if idle >= DEAD_AFTER_IDLE
        @logger.warn "No data from Slack in #{idle.round}s; reconnecting Socket Mode"
        return :dead
      end
      return if idle < PING_AFTER_IDLE

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if @last_ping_at && now - @last_ping_at < PING_INTERVAL

      @last_ping_at = now
      connection.ping
    end

    def wait(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      sleep(0.2) while !stopped? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end

    def web_client
      @web_client ||= Slack::Web::Client.new(token: @app_token)
    end
  end
end

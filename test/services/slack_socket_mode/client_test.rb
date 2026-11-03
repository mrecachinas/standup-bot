require "test_helper"

class SlackSocketMode::ClientTest < ActiveSupport::TestCase
  # Plays back a scripted list of messages, then reports itself closed.
  class FakeConnection
    attr_reader :sent, :pings
    attr_accessor :on_close

    def initialize(messages, idle: 0)
      @messages = messages.map { |message| message.is_a?(String) ? message : message.to_json }
      @idle = idle
      @sent = []
      @pings = 0
      @closed = false
    end

    def open = self
    def read(timeout:) = @messages.empty? ? (@closed = true; []) : [ @messages.shift ]
    def send_text(text) = @sent << JSON.parse(text)
    def ping = @pings += 1
    def idle_seconds = @idle
    def closed? = @closed
    def close
      @closed = true
      on_close&.call
    end
  end

  setup do
    @web_client = stub("web_client", apps_connections_open: { "url" => "wss://wss.slack.example/link" })
    @dispatcher = mock("dispatcher")
    @logger = ActiveSupport::Logger.new(StringIO.new)
  end

  test "dispatches envelopes and sends their acks over the socket" do
    connection = FakeConnection.new([
      { type: "hello", num_connections: 1 },
      { envelope_id: "env-1", type: "events_api", payload: {} },
      { type: "disconnect", reason: "refresh_requested" }
    ])
    client = build_client([ connection ])
    @dispatcher.expects(:call).with { |envelope| envelope["envelope_id"] == "env-1" }.yields({ envelope_id: "env-1" })
    StandupMetrics.expects(:track).with(SlackSocketMode::Client::CONNECTED_METRIC, connections: 1)

    client.run

    assert_equal [ { "envelope_id" => "env-1" } ], connection.sent
  end

  test "reconnects after Slack asks it to, without backing off" do
    first = FakeConnection.new([ { type: "hello" }, { type: "disconnect", reason: "refresh_requested" } ])
    second = FakeConnection.new([ { type: "hello" } ])
    client = build_client([ first, second ])
    delays = record_waits(client)

    client.run

    assert_empty delays

    assert first.closed?
    assert second.closed?
  end

  test "keeps going after a malformed message or a failed envelope" do
    connection = FakeConnection.new([ { type: "hello" }, "not json", { envelope_id: "env-1", type: "interactive" }, { envelope_id: "env-2", type: "interactive" } ])
    @dispatcher.expects(:call).with { |envelope| envelope["envelope_id"] == "env-1" }.raises(StandardError, "boom")
    @dispatcher.expects(:call).with { |envelope| envelope["envelope_id"] == "env-2" }.yields({ envelope_id: "env-2" })

    build_client([ connection ]).run

    assert_equal [ { "envelope_id" => "env-2" } ], connection.sent
  end

  test "pings when idle and drops a dead connection" do
    quiet = FakeConnection.new([ { type: "hello" } ] + Array.new(3, "{}"), idle: SlackSocketMode::Client::PING_AFTER_IDLE)
    dead = FakeConnection.new([ { type: "hello" } ] + Array.new(3, "{}"), idle: SlackSocketMode::Client::DEAD_AFTER_IDLE)

    build_client([ quiet ]).run
    build_client([ dead ]).run

    assert_equal 1, quiet.pings
    assert_equal 0, dead.pings
    assert dead.closed?
  end

  test "backs off when it can't connect" do
    @web_client.stubs(:apps_connections_open).raises(Slack::Web::Api::Errors::SlackError.new("invalid_auth"))
    client = build_client([])
    delays = record_waits(client, stop_after: 3)

    client.run

    assert_equal [ 1, 2, 5 ], delays
  end

  test "requires an app-level token" do
    error = assert_raises(ArgumentError) { SlackSocketMode::Client.new(app_token: nil, logger: @logger).run }
    assert_match "SLACK_APP_TOKEN", error.message
  end

  private

  def record_waits(client, stop_after: nil)
    delays = []
    client.define_singleton_method(:wait) do |seconds|
      delays << seconds
      stop if delays.size == stop_after
    end
    delays
  end

  # Stops the client once the last scripted connection closes.
  def build_client(connections)
    client = SlackSocketMode::Client.new(
      app_token: "xapp-test",
      dispatcher: @dispatcher,
      logger: @logger,
      web_client: @web_client,
      connection_factory: lambda do |_url|
        connection = connections.shift || raise(SlackSocketMode::Connection::Error, "no more connections")
        connection.on_close = -> { client.stop } if connections.empty?
        connection
      end
    )
  end
end

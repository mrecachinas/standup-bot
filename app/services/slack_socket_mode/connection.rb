require "openssl"
require "socket"
require "uri"
require "websocket/driver"

module SlackSocketMode
  # A minimal blocking WebSocket client over TLS. websocket-driver (bundled
  # with Action Cable) handles framing, the handshake, and answering pings.
  class Connection
    READ_SIZE = 16 * 1024
    WRITE_TIMEOUT = 10

    class Error < StandardError; end

    attr_reader :url

    def initialize(url, open_timeout: 10)
      @url = url
      @uri = URI.parse(url)
      raise ArgumentError, "Socket Mode URL must be wss://" unless @uri.scheme == "wss" && @uri.host.present?

      @open_timeout = open_timeout
      @messages = []
      @closed = false
    end

    def open
      @socket = tls_socket
      @driver = WebSocket::Driver.client(self)
      @driver.on(:message) { |event| @messages << event.data }
      @driver.on(:close) { @closed = true }
      @driver.on(:error) { |event| raise Error, event.message }
      @driver.start
      @last_received_at = monotonic_now
      self
    end

    # Called by websocket-driver with bytes to send.
    def write(data)
      @socket.write(data)
    end

    # Waits up to +timeout+ seconds for data and returns any complete text messages.
    def read(timeout:)
      return [] if closed?
      return [] unless @socket.pending.positive? || IO.select([ @socket.to_io ], nil, nil, timeout)

      data = @socket.read_nonblock(READ_SIZE, exception: false)
      case data
      when nil
        @closed = true
      when String
        @last_received_at = monotonic_now
        @driver.parse(data)
      end

      @messages.shift(@messages.size)
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      @closed = true
      []
    end

    def send_text(text)
      @driver.text(text)
    end

    def ping
      @driver.ping
    end

    def idle_seconds
      monotonic_now - @last_received_at
    end

    def closed?
      @closed
    end

    def close
      @closed = true
      begin
        @driver&.close
      rescue StandardError
        nil
      end
      @socket&.close
    rescue StandardError
      nil
    end

    private

    def tls_socket
      host = @uri.host
      tcp = Socket.tcp(host, @uri.port || 443, connect_timeout: @open_timeout)
      context = OpenSSL::SSL::SSLContext.new
      context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      socket = OpenSSL::SSL::SSLSocket.new(tcp, context)
      socket.hostname = host
      socket.sync_close = true
      handshake(socket, tcp)
      socket.post_connection_check(host)
      # Bounds blocking writes (acks, pings) so a stalled peer can't hang the client.
      tcp.timeout = WRITE_TIMEOUT
      socket
    rescue StandardError
      tcp&.close
      raise
    end

    # connect_timeout only covers TCP, so give the TLS handshake its own deadline.
    def handshake(socket, tcp)
      deadline = monotonic_now + @open_timeout
      begin
        socket.connect_nonblock
      rescue IO::WaitReadable, IO::WaitWritable => wait
        remaining = deadline - monotonic_now
        ready = remaining.positive? && (wait.is_a?(IO::WaitReadable) ? IO.select([ tcp ], nil, nil, remaining) : IO.select(nil, [ tcp ], nil, remaining))
        raise Error, "TLS handshake with #{@uri.host} timed out" unless ready

        retry
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

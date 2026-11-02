require "puma/plugin"

# Runs the Slack Socket Mode client on a thread inside Puma, so a single web
# process can receive Slack traffic without a separate bin/slack-socket-mode.
# Enabled with SLACK_SOCKET_MODE_IN_PUMA=1 (see config/puma.rb). The thread
# needs the app loaded in the Puma process, which is the case in single mode
# (the default here) or in cluster mode with preload_app!.
Puma::Plugin.create do
  def start(launcher)
    after_booted = launcher.events.respond_to?(:after_booted) ? :after_booted : :on_booted
    after_stopped = launcher.events.respond_to?(:after_stopped) ? :after_stopped : :on_stopped

    launcher.events.public_send(after_booted) do
      next launcher.log_writer.log("* Slack Socket Mode: SLACK_CONNECTION_MODE isn't \"socket\", not starting") unless SlackConfig.socket_mode?

      @slack_socket_mode = SlackSocketMode::Client.new
      Thread.new do
        Thread.current.name = "slack-socket-mode"
        @slack_socket_mode.run
      rescue StandardError => error
        launcher.log_writer.log("! Slack Socket Mode stopped: #{error.class}: #{error.message}")
      end
      launcher.log_writer.log("* Slack Socket Mode: started in Puma")
    end

    launcher.events.public_send(after_stopped) { @slack_socket_mode&.stop }
  end
end

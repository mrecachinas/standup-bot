module Instrumentation
  # Logs the app's own Rails.event events as one line each:
  #
  #   {"event":"standup.sent","payload":{"standup_id":1,…}, …context}
  #
  # Rails' framework events are skipped; Lograge and Active Job log those.
  class LogSubscriber
    def initialize(logger: nil)
      @logger = logger
    end

    def emit(event)
      return if Instrumentation.framework_event?(event[:name])

      payload = event[:payload]
      payload = payload.to_h if !payload.is_a?(Hash) && payload.respond_to?(:to_h)
      entry = { event: event[:name], payload: payload }
      entry[:event_tags] = event[:tags] if event[:tags].present?

      logger.info(entry)
    end

    private

    def logger
      @logger || Rails.logger
    end
  end
end

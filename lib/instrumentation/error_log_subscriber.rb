module Instrumentation
  # The default Rails.error backend: writes each reported error as a structured
  # log line. An error tracker subscribed alongside it gets the same reports.
  class ErrorLogSubscriber
    BACKTRACE_LINES = 20
    LEVELS = { error: :error, warning: :warn, info: :info }.freeze

    def initialize(logger: nil, backtrace_cleaner: nil)
      @logger = logger
      @backtrace_cleaner = backtrace_cleaner
    end

    def report(error, handled:, severity:, context:, source:)
      entry = {
        event: "error.reported",
        error_class: error.class.name,
        error_message: error.message,
        handled: handled,
        severity: severity,
        source: source,
        cause: error.cause&.class&.name,
        backtrace: backtrace(error),
        context: filter(context)
      }.compact

      logger.public_send(LEVELS.fetch(severity, :error), entry)
    end

    private

    def logger
      @logger || Rails.logger
    end

    def backtrace(error)
      lines = error.backtrace || []
      cleaner = @backtrace_cleaner || (Rails.backtrace_cleaner if defined?(Rails.backtrace_cleaner))
      cleaned = cleaner ? cleaner.clean(lines) : lines
      (cleaned.presence || lines).first(BACKTRACE_LINES)
    end

    def filter(context)
      return {} if context.blank?

      ActiveSupport::ParameterFilter.new(ActiveSupport.filter_parameters).filter(Instrumentation.serializable(context))
    end
  end
end

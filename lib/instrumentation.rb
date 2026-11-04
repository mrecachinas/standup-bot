require "json"
require "active_support"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/object/json"
require "active_support/tagged_logging"

# Logs, metrics, and error reports, built on Rails' own pluggable reporters:
#
# * Errors go to +Rails.error+. Rails reports unhandled request and job errors
#   by itself; call +Rails.error.report+ for ones the app rescues.
# * Events go to +Rails.event+ (see StandupMetrics.track). Rails also emits
#   request and job events there, with durations.
#
# A backend is a subscriber: anything with +report(error, handled:, severity:,
# context:, source:)+ for errors, or +emit(event)+ for events. Instrumentation.install!
# subscribes the built-in ones (JSON logs, and StatsD when STATSD_ADDR is set).
# To add another, such as an error tracker, subscribe it in an initializer:
#
#   Rails.error.subscribe(MyErrorTracker.new)
#   Rails.event.subscribe(MyMetrics.new)
#
# This file isn't autoloaded (it's required from config/application.rb), so
# config/environments can use the log formatter.
module Instrumentation
  # Rails' own structured events. Logged elsewhere already (Lograge, Active
  # Job's logger), so the log subscriber skips them.
  FRAMEWORK_EVENT_PREFIXES = %w[
    action_controller. action_dispatch. action_mailer. action_view.
    active_job. active_record. active_storage. active_support.
  ].freeze

  class << self
    # Subscribes the built-in backends. Call once, from an initializer.
    def install!(event_reporter: ActiveSupport.event_reporter, error_reporter: ActiveSupport.error_reporter, env: ENV)
      event_reporter.subscribe(LogSubscriber.new)
      error_reporter.subscribe(ErrorLogSubscriber.new)

      if (address = env["STATSD_ADDR"].presence)
        statsd = StatsdSubscriber.new(address: address, prefix: env.fetch("STATSD_PREFIX", StatsdSubscriber::DEFAULT_PREFIX))
        event_reporter.subscribe(statsd)
        error_reporter.subscribe(statsd)
      end
    end

    # Adds to the context that every log line, event, and error report in the
    # current request or job carries (request_id, user_id, job_id, ...). Rails
    # clears it when the request or job finishes.
    def set_context(**context)
      context = context.compact
      return if context.empty?

      ActiveSupport.event_reporter.set_context(context)
      ActiveSupport.error_reporter.set_context(**context)
    end

    # Sets context for the block only: when it exits, even by raising, both
    # reporters' contexts go back to what they were, dropping anything set
    # inside. Keys that weren't set before are left as nil in the error
    # context, which has no way to remove one.
    def with_context(**context)
      event_context = ActiveSupport.event_reporter.context
      error_context = ActiveSupport::ExecutionContext.to_h
      begin
        set_context(**context)
        yield
      ensure
        ActiveSupport.event_reporter.clear_context
        ActiveSupport.event_reporter.set_context(event_context)
        added_keys = ActiveSupport::ExecutionContext.to_h.keys - error_context.keys
        ActiveSupport::ExecutionContext.set(**added_keys.index_with(nil), **error_context)
      end
    end

    def context
      ActiveSupport.event_reporter.context
    end

    def framework_event?(name)
      FRAMEWORK_EVENT_PREFIXES.any? { |prefix| name.to_s.start_with?(prefix) }
    end

    # A JSON-safe copy of a log or report value. Objects other than plain data
    # become their class name, so a stray model can't dump its attributes.
    def serializable(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = serializable(item) }
      when Array then value.map { |item| serializable(item) }
      when String
        value.encoding == Encoding::UTF_8 && value.valid_encoding? ? value : value.dup.force_encoding(Encoding::UTF_8).scrub
      when Symbol then value.to_s
      when Numeric, true, false, nil then value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601(3)
      when Date then value.iso8601
      when Exception then value.class.name
      else
        if defined?(ActiveJob::Base) && value.is_a?(ActiveJob::Base)
          "#{value.class.name}##{value.job_id}"
        elsif defined?(AbstractController::Base) && value.is_a?(AbstractController::Base)
          "#{value.class.name}##{value.action_name}"
        else
          value.class.name
        end
      end
    end
  end
end

require_relative "instrumentation/json_log_formatter"
require_relative "instrumentation/log_subscriber"
require_relative "instrumentation/error_log_subscriber"
require_relative "instrumentation/statsd_subscriber"
require_relative "instrumentation/request_context"

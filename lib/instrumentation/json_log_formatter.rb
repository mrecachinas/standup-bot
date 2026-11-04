require "logger"

module Instrumentation
  # Writes each log line as one JSON object:
  #
  #   {"time":"…","level":"INFO","request_id":"…","user_id":1,"message":"…"}
  #
  # String messages go under "message"; Hash messages (Lograge, events, error
  # reports) are merged in. The current Instrumentation.context is added to
  # every line, and any TaggedLogging tags (such as Active Job's) go under "tags".
  class JsonLogFormatter < ::Logger::Formatter
    # Including it here, rather than having TaggedLogging extend the formatter
    # later, keeps our #call ahead of the one that prepends "[tag]" text.
    include ActiveSupport::TaggedLogging::Formatter

    def call(severity, time, _progname, message)
      entry = { "time" => time.utc.iso8601(3), "level" => severity }
      tags = current_tags
      entry["tags"] = tags.dup if tags.any?
      entry.merge!(Instrumentation.serializable(Instrumentation.context))
      entry.merge!(message_fields(message))

      "#{JSON.generate(entry)}\n"
    rescue StandardError => error
      fallback = { "time" => time.utc.iso8601(3), "level" => severity, "message" => message.inspect.scrub, "log_error" => error.class.name }
      "#{JSON.generate(fallback)}\n"
    end

    private

    def message_fields(message)
      case message
      when Hash
        Instrumentation.serializable(message)
      when Exception
        { "message" => message.message.to_s.scrub, "error_class" => message.class.name }
      when String
        { "message" => Instrumentation.serializable(message) }
      else
        { "message" => message.inspect.scrub }
      end
    end
  end
end

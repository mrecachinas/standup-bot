# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.lograge.enabled = true
  # With the JSON log formatter, Lograge hands it a Hash to merge with the
  # line's context; otherwise it writes its own JSON.
  config.lograge.formatter =
    if config.logger&.formatter.is_a?(Instrumentation::JsonLogFormatter)
      Lograge::Formatters::Raw.new
    else
      Lograge::Formatters::Json.new
    end

  config.lograge.custom_payload do |controller|
    request = controller.request

    {
      host: request.host,
      user_agent: request.user_agent,
      request_id: request.request_id
    }
  end

  # Set by controllers in append_info_to_payload (see Api::BaseController).
  config.lograge.custom_options = lambda do |event|
    event.payload.slice(:user_id, :member).compact
  end
end

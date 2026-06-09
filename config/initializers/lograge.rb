# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_payload do |controller|
    request = controller.request

    {
      host: request.host,
      user_agent: request.user_agent,
      request_id: request.request_id
    }
  end
end

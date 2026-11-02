Rails.application.config.after_initialize do
  SlackConfig.validate!
end

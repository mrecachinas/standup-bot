module Microsoft
  # Reads config/teams.yml (Rails.application.config.teams).
  module Config
    module_function

    def value(key)
      config = Rails.application.config.teams || {}
      (config[key] || config[key.to_s]).presence
    end

    def app_id = value(:app_id)
    def app_password = value(:app_password)
    def tenant_id = value(:tenant_id)
    def service_url = value(:service_url) || "https://smba.trafficmanager.net/teams/"
    def app_catalog_id = value(:app_catalog_id)
    def sign_in_client_id = value(:sign_in_client_id) || app_id
    def sign_in_client_secret = value(:sign_in_client_secret) || app_password

    def bot_configured?
      app_id.present? && app_password.present? && tenant_id.present?
    end
  end
end

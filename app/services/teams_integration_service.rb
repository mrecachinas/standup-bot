class TeamsIntegrationService < ChatIntegrationService
  CREDENTIALS = [
    { key: :app_id, label: "App (client) ID", env: "TEAMS_APP_ID", required: true },
    { key: :app_password, label: "Client secret", env: "TEAMS_APP_PASSWORD", required: true, secret: true },
    { key: :tenant_id, label: "Tenant ID", env: "TEAMS_TENANT_ID", required: true },
    { key: :app_catalog_id, label: "App catalog ID (auto-install)", env: "TEAMS_APP_CATALOG_ID", required: false },
    { key: :sign_in_client_secret, label: "Sign-in client secret", env: "TEAMS_SIGN_IN_CLIENT_SECRET", required: false, secret: true }
  ].freeze
  API_CREDENTIALS = %i[app_id app_password tenant_id].freeze

  def initialize(client: ChatPlatform.for(:teams), config: Rails.application.config.teams)
    super
  end

  private

  def installed_message
    "Teams bot credentials are configured."
  end

  def missing_installation_message
    "Register the Azure Bot and set TEAMS_APP_ID, TEAMS_APP_PASSWORD, and TEAMS_TENANT_ID before using Teams actions."
  end

  def user_lookup_hint
    "a Teams name, email, or Entra object ID"
  end

  def error_code_for(error)
    return "teams_app_not_installed" if error.is_a?(ChatPlatform::TeamsAdapter::NotInstalled)
    return "credentials_rejected" if error.is_a?(Microsoft::CredentialsRejected)
    return "forbidden" if error.is_a?(Microsoft::ApiError) && error.forbidden?
    return "not_found" if error.is_a?(Microsoft::ApiError) && error.not_found?

    super
  end

  def error_message_for(error_code, error, operation)
    case error_code
    when "teams_app_not_installed"
      sanitized_error_message(error)
    when "credentials_rejected"
      "Microsoft rejected the Teams app credentials (#{error.code || error.status})."
    when "forbidden"
      "Microsoft denied access while trying to #{operation}."
    when "not_found"
      "Microsoft couldn't find that team, channel, or user."
    else
      super
    end
  end

  def action_for(error_code)
    case error_code
    when "teams_app_not_installed"
      "Install the Standup Bot app for that person, or set TEAMS_APP_CATALOG_ID."
    when "credentials_rejected"
      "Check TEAMS_APP_ID, TEAMS_APP_PASSWORD, and TEAMS_TENANT_ID match the bot's app registration."
    when "forbidden"
      "Check the Graph application permissions have admin consent, and that the bot is installed in the team."
    when "not_found"
      "Pick the channel or person again from discovery."
    else
      super
    end
  end
end

# The bearer token scripts use for /api. Shared by Api::BaseController and the
# Rack::Attack ban on repeated bad tokens.
module AdminApiToken
  module_function

  def configured
    ENV["ADMIN_API_TOKEN"].presence ||
      Rails.application.credentials.dig(:admin, :api_token).presence ||
      Rails.application.credentials.dig(:admin_api_token).presence
  end

  def configured?
    configured.present?
  end

  def valid?(provided)
    token = configured
    provided = provided.to_s
    token.present? && provided.bytesize == token.bytesize && ActiveSupport::SecurityUtils.secure_compare(provided, token)
  end

  def from_header(authorization)
    authorization.to_s[/\ABearer (.+)\z/, 1].to_s
  end
end

# Signs in to the JSON API and builds bearer-token headers. Included in every
# ActionDispatch::IntegrationTest by test_helper.rb.
module ApiTestHelper
  ADMIN_TOKEN = "admin-access-token".freeze

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end

  def token_headers(token = ADMIN_TOKEN)
    { "Authorization" => "Bearer #{token}" }
  end
end

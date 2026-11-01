require "test_helper"

# How /api decides who is calling. Token requests and cookie requests share
# controllers, so these pin the boundary between them.
class Api::AuthenticationTest < ActionDispatch::IntegrationTest
  ADMIN_TOKEN = "test-admin-token".freeze

  setup do
    @previous_admin_token = ENV["ADMIN_API_TOKEN"]
    ENV["ADMIN_API_TOKEN"] = ADMIN_TOKEN
    @owned = standups(:daily)
    @not_owned = standups(:weekly)
  end

  teardown do
    ENV["ADMIN_API_TOKEN"] = @previous_admin_token
  end

  test "rejects requests with no credentials" do
    get api_standups_path, as: :json
    assert_response :unauthorized
  end

  test "the admin token sees every standup" do
    get api_standups_path, headers: token_headers, as: :json

    assert_response :success
    assert_equal Standup.count, response.parsed_body["standups"].size
  end

  test "a wrong token is rejected even with a valid session cookie" do
    sign_in(users(:admin), "admin-access-token")

    get api_standups_path, headers: { "Authorization" => "Bearer wrong" }, as: :json
    assert_response :unauthorized
  end

  test "an empty Authorization header is still a token request" do
    sign_in(users(:admin), "admin-access-token")

    get api_standups_path, headers: { "Authorization" => "" }, as: :json
    assert_response :unauthorized
  end

  test "a manager's session only lists the standups they manage" do
    sign_in(users(:manager), "manager-access-token")

    get api_standups_path, as: :json

    assert_response :success
    assert_equal [ @owned.id ], response.parsed_body["standups"].map { |standup| standup["id"] }
  end

  test "a manager's session can't read a standup they don't manage" do
    sign_in(users(:manager), "manager-access-token")

    get api_standup_path(@not_owned), as: :json
    assert_response :forbidden

    get api_standup_participants_path(@not_owned), as: :json
    assert_response :forbidden

    get api_standup_path(@owned), as: :json
    assert_response :success
  end

  test "an admin's session sees every standup" do
    sign_in(users(:admin), "admin-access-token")

    get api_standup_path(@not_owned), as: :json
    assert_response :success
  end

  test "creating a standup from a session makes the creator an owner" do
    sign_in(users(:manager), "manager-access-token")

    post api_standups_path, params: { standup: standup_attributes }, as: :json

    assert_response :created
    standup = Standup.find(response.parsed_body.dig("standup", "id"))
    assert standup.manageable_by?(users(:manager))
    log = AuditLog.where(action: "standup.create", auditable: standup).sole
    assert_equal users(:manager).id, log.actor_id
  end

  test "creating a standup with the token makes no owner and audits as the admin API" do
    post api_standups_path, params: { standup: standup_attributes }, headers: token_headers, as: :json

    assert_response :created
    standup = Standup.find(response.parsed_body.dig("standup", "id"))
    assert_empty standup.standup_ownerships
    log = AuditLog.where(action: "standup.create", auditable: standup).sole
    assert_nil log.actor_id
    assert_equal "admin_api", log.actor_label
    assert_equal "admin_api_token", log.metadata["auth_method"]
  end

  test "validation errors keep the message array and add field errors" do
    post api_standups_path, params: { standup: { name: "" } }, headers: token_headers, as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_kind_of Array, body["errors"]
    assert body["field_errors"].key?("name")
  end

  test "session endpoints refuse the token" do
    get api_session_path, headers: token_headers, as: :json
    assert_response :forbidden
  end

  test "member endpoints refuse the token" do
    get api_me_standups_path, headers: token_headers, as: :json
    assert_response :forbidden
  end

  test "signing in returns the bootstrap payload" do
    post api_session_path, params: { email: users(:manager).email, access_token: "manager-access-token" }, as: :json

    assert_response :created
    body = response.parsed_body
    assert body["authenticated"]
    assert_equal users(:manager).email, body.dig("user", "email")
    assert_equal [ @owned.id ], body["sidebar_standups"].map { |standup| standup["id"] }
    assert_equal ChatPlatform.keys.map(&:to_s), body["platforms"].map { |platform| platform["key"] }
    assert body["csrf_token"].present?
  end

  test "a wrong access token doesn't sign in" do
    post api_session_path, params: { email: users(:manager).email, access_token: "nope" }, as: :json

    assert_response :unauthorized
    get api_session_path, as: :json
    assert_not response.parsed_body["authenticated"]
  end

  test "signing out ends the session" do
    sign_in(users(:manager), "manager-access-token")

    delete api_session_path, as: :json
    assert_response :success

    get api_standups_path, as: :json
    assert_response :unauthorized
  end

  test "the bootstrap hands over flash messages once" do
    SlackSignIn.stubs(:configured?).returns(false)
    get "/auth/slack"

    get api_session_path, as: :json
    assert_equal [ "danger" ], response.parsed_body["flash"].map { |message| message["type"] }

    get api_session_path, as: :json
    assert_empty response.parsed_body["flash"]
  end

  test "cookie requests that change data need the CSRF token" do
    with_forgery_protection do
      get api_session_path, as: :json
      csrf_token = response.parsed_body["csrf_token"]

      post api_session_path, params: { email: users(:manager).email, access_token: "manager-access-token" }, as: :json
      assert_response :unprocessable_entity

      post api_session_path,
        params: { email: users(:manager).email, access_token: "manager-access-token" },
        headers: { "X-CSRF-Token" => csrf_token },
        as: :json
      assert_response :created
      csrf_token = response.parsed_body["csrf_token"]

      post api_standups_path, params: { standup: standup_attributes }, as: :json
      assert_response :unprocessable_entity

      post api_standups_path, params: { standup: standup_attributes }, headers: { "X-CSRF-Token" => csrf_token }, as: :json
      assert_response :created
    end
  end

  test "token requests don't need a CSRF token" do
    with_forgery_protection do
      post api_standups_path, params: { standup: standup_attributes }, headers: token_headers, as: :json
      assert_response :created
    end
  end

  private

  def token_headers
    { "Authorization" => "Bearer #{ADMIN_TOKEN}" }
  end

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end

  def standup_attributes
    { name: "API standup", platform: "slack", platform_channel: "#api-standup", questions: [ "How's it going?" ], schedule_type: "weekdays", default_hour: 9, default_minute: 0 }
  end

  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end

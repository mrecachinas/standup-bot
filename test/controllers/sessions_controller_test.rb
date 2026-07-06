require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "does not prefill local admin credentials outside development" do
    with_env("MANAGER_ADMIN_EMAIL" => "admin@example.com", "MANAGER_ADMIN_TOKEN" => "local-manager-token") do
      get new_session_path
    end

    assert_response :success
    assert_not_includes response.body, "local-manager-token"
    assert_not_includes response.body, "Local development credentials are pre-filled"
  end

  test "prefills local admin credentials in development" do
    Rails.env.stubs(:development?).returns(true)

    with_env("MANAGER_ADMIN_EMAIL" => "admin@example.com", "MANAGER_ADMIN_TOKEN" => "local-manager-token") do
      get new_session_path
    end

    assert_response :success
    assert_includes response.body, "admin@example.com"
    assert_includes response.body, "local-manager-token"
    assert_includes response.body, "Local development credentials are pre-filled"
  end

  test "signs in with email and access token" do
    post session_path, params: { email: "manager@example.com", access_token: "manager-access-token" }

    assert_redirected_to manager_standups_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Daily Standup"
  end

  test "rejects invalid token" do
    post session_path, params: { email: "manager@example.com", access_token: "wrong-token" }

    assert_response :unauthorized
    assert_includes response.body, "Invalid email or access token"
  end

  test "signs out through method override form post" do
    post session_path, params: { email: "manager@example.com", access_token: "manager-access-token" }
    assert_redirected_to manager_standups_path

    post session_path, params: { _method: "delete" }

    assert_redirected_to new_session_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Manager sign in"
  end

  private

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

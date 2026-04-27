require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
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

  test "signs out from method override form posts" do
    post session_path, params: { email: "manager@example.com", access_token: "manager-access-token" }
    assert_redirected_to manager_standups_path

    post session_path, params: { _method: "delete" }

    assert_redirected_to new_session_path
    get manager_standups_path
    assert_redirected_to new_session_path
  end
end

require "test_helper"

class SpaControllerTest < ActionDispatch::IntegrationTest
  test "serves the app for console deep links" do
    get "/manager/standups/123/some-new-page"

    assert_response :success
    assert_includes response.body, %(<div id="root">)
    assert_equal "no-cache", response.headers["Cache-Control"]
  end

  test "never captures API, chat, auth, or health paths" do
    %w[/api/nope /slack/nope /teams/nope /auth/nope /health/nope /app/missing.js].each do |path|
      get path
      assert_response :not_found, "#{path} shouldn't be served by the SPA"
    end
  end

  test "doesn't serve the app for non-HTML requests" do
    get "/some/page.json"
    assert_response :not_found
  end
end

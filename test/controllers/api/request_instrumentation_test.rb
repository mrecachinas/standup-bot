require "test_helper"

class Api::RequestInstrumentationTest < ActionDispatch::IntegrationTest
  test "request logs, events, and error reports know the request and the user" do
    admin = users(:admin)
    seen = []
    capture = lambda do |event|
      seen << { payload: event.payload, event_context: Instrumentation.context.dup, error_context: ActiveSupport::ExecutionContext.to_h }
    end

    ActiveSupport::Notifications.subscribed(capture, "process_action.action_controller") do
      get api_standups_path, headers: token_headers.merge("X-Request-Id" => "req-123")
    end

    assert_response :success
    request = seen.sole
    assert_equal admin.id, request[:payload][:user_id]
    assert_equal({ request_id: "req-123", user_id: admin.id }, request[:event_context].slice(:request_id, :user_id))
    assert_equal({ request_id: "req-123", user_id: admin.id }, request[:error_context].slice(:request_id, :user_id))
  end
end

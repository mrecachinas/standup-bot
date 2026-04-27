require "test_helper"
require "timecop"

class SlackEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Mock the verify_slack_request before_action to always return true for testing
    SlackEventsController.any_instance.stubs(:verify_slack_request).returns(true)
    # Make sure we're not actually calling the real method
    SlackSignatureVerifier.stubs(:verify).returns(true)
    # Also stub the `skip_before_action` to avoid the callback issue
    ApplicationController.any_instance.stubs(:verify_authenticity_token).returns(nil)
  end

  test "should handle url verification challenge" do
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0)) do
      challenge_code = "verification_challenge_123"

      post events_url, params: {
        type: "url_verification",
        challenge: challenge_code
      }, as: :json

      assert_response :success
      response_body = JSON.parse(response.body)
      assert_equal challenge_code, response_body["challenge"]
    end
  end

  test "should reject invalid url verification challenge" do
    post events_url, params: {
      type: "url_verification",
      challenge: "<script>alert(1)</script>"
    }, as: :json

    assert_response :bad_request
  end

  test "install endpoint is protected by slack verification" do
    callback = SlackEventsController._process_action_callbacks.find do |registered_callback|
      registered_callback.kind == :before && registered_callback.filter == :verify_slack_request
    end

    assert_not_nil callback
    assert_empty Array(callback.instance_variable_get(:@if))
    assert_empty Array(callback.instance_variable_get(:@unless))
  end

  test "should enqueue event processor job for regular events" do
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0)) do
      event_data = {
        type: "message",
        user: "U12345",
        text: "Hello, world!",
        channel: "C67890",
        ts: "1234567890.123456"
      }

      assert_enqueued_with(job: SlackEventProcessorJob) do
        post events_url, params: {
          event: event_data
        }
      end

      assert_response :success # Check for head :ok
    end
  end

  test "should handle missing parameters gracefully" do
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0)) do
      # Instead of expecting an exception, check the response status
      post events_url, as: :json
      assert_response :bad_request # HTTP 400 status code
    end
  end

  test "should extract only permitted parameters" do
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0)) do
      event_data = {
        type: "message",
        user: "U12345",
        text: "Hello, world!",
        channel: "C67890",
        ts: "1234567890.123456",
        unpermitted_param: "should_be_filtered"
      }

      # Use a test spy to capture what's passed to perform_later
      SlackEventProcessorJob.expects(:perform_later).with do |passed_params|
        # Check that unpermitted_param is not included
        assert_not passed_params.key?("unpermitted_param")

        # Check that permitted params are included
        assert_equal "message", passed_params["type"]
        assert_equal "U12345", passed_params["user"]
        assert_equal "Hello, world!", passed_params["text"]
        assert_equal "C67890", passed_params["channel"]
        assert_equal "1234567890.123456", passed_params["ts"]

        true # Return true to satisfy the expectation
      end

      post events_url, params: { event: event_data }
      assert_response :success
    end
  end

  test "should log event details" do
    Timecop.freeze(Time.new(2025, 4, 6, 10, 0, 0)) do
      event_data = {
        type: "message",
        user: "U12345",
        text: "Hello, world!",
        channel: "C67890",
        ts: "1234567890.123456"
      }

      # Temporarily replace the logger to capture output
      log_output = StringIO.new
      original_logger = Rails.logger
      begin
        # Use a simple logger that writes to our string buffer
        Rails.logger = Logger.new(log_output)

        post events_url, params: { event: event_data }
        assert_response :success

        # Check the log content
        log_output.rewind
        log_content = log_output.read
        assert_match(/Received Slack event=message subtype= from user=U12345 in channel=C67890/, log_content)
      ensure
        # Restore the original logger
        Rails.logger = original_logger
      end
    end
  end

  test "should handle standup selection interactions" do
    standup = standups(:daily)
    participant = standup_participants(:one)
    participant.update!(cached_timezone: "UTC", cached_timezone_updated_at: Time.current)
    payload = {
      type: "block_actions",
      user: { id: participant.slack_id },
      actions: [
        {
          action_id: "standup_selection",
          selected_option: { value: standup.id.to_s }
        }
      ]
    }

    assert_enqueued_with(job: StandupCollectionJob, args: [ standup.id, participant.standup_date_for(Time.current).iso8601, "Etc/UTC" ]) do
      post interactions_url, params: { payload: payload.to_json }
    end

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "ephemeral", response_body["response_type"]
    assert_match(/Generating report/, response_body["text"])
  end

  test "should reject invalid interaction payload" do
    post interactions_url, params: { payload: "not json" }

    assert_response :bad_request
  end
end

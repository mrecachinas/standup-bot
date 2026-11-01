require "test_helper"
require_relative "../support/teams_test_helper"

class TeamsActivitiesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include TeamsTestHelper

  setup do
    enable_teams!
  end

  def activity(overrides = {})
    {
      "type" => "message",
      "id" => "1",
      "text" => "Did things",
      "serviceUrl" => TEAMS_SERVICE_URL,
      "channelId" => "msteams",
      "from" => { "id" => "29:abc", "aadObjectId" => TEAMS_USER_ID },
      "conversation" => { "id" => "a:chat", "conversationType" => "personal", "tenantId" => TEAMS_TENANT_ID },
      "attachments" => [ { "contentType" => "text/html" } ]
    }.merge(overrides)
  end

  def post_activity(body, token: "valid")
    post teams_messages_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  test "queues verified activities without attachments" do
    Microsoft::BotFrameworkAuth.any_instance.expects(:verify!).with("Bearer valid", service_url: TEAMS_SERVICE_URL, channel_id: "msteams").returns({})

    assert_enqueued_with(job: TeamsActivityProcessorJob) do
      post_activity(activity)
    end

    assert_response :ok
    queued = enqueued_jobs.last[:args].first
    assert_equal "Did things", queued["text"]
    assert_not queued.key?("attachments")
  end

  test "rejects requests without a valid Bot Framework token" do
    Microsoft::BotFrameworkAuth.any_instance.expects(:verify!).raises(Microsoft::BotFrameworkAuth::Unauthorized, "bad token")

    assert_no_enqueued_jobs { post_activity(activity, token: "forged") }
    assert_response :unauthorized
  end

  test "rejects activities from another tenant" do
    Microsoft::BotFrameworkAuth.any_instance.stubs(:verify!).returns({})

    assert_no_enqueued_jobs do
      post_activity(activity("conversation" => { "id" => "a:chat", "tenantId" => "00000000-0000-0000-0000-000000000000" }))
    end
    assert_response :forbidden
  end

  test "ignores activities from other channels" do
    Microsoft::BotFrameworkAuth.any_instance.stubs(:verify!).returns({})

    assert_no_enqueued_jobs { post_activity(activity("channelId" => "webchat")) }
    assert_response :ok
  end

  test "rejects malformed JSON" do
    post teams_messages_path, params: "{not json", headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
  end
end

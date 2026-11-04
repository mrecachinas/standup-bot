require "test_helper"

class SlackInteractionJobTest < ActiveJob::TestCase
  setup do
    @participant = standup_participants(:one)
    @participant.update!(cached_timezone: "UTC", cached_timezone_updated_at: Time.current)
    @http = mock("http")
    SlackInteractionJob.any_instance.stubs(:http).returns(@http)
  end

  test "handles the click and replies through the response_url" do
    standup = standups(:daily)
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://hooks.slack.com/actions/T1/123/abc",
      "actions" => [ { "action_id" => "standup_selection", "selected_option" => { "value" => standup.id.to_s } } ]
    }
    @http.expects(:post).with do |url, body, headers|
      assert_equal payload["response_url"], url
      assert_match(/Generating report/, JSON.parse(body)["text"])
      assert_equal "application/json", headers["Content-Type"]
      true
    end

    assert_enqueued_with(job: StandupCollectionJob) do
      SlackInteractionJob.perform_now(payload)
    end
  end

  test "won't post replies to a non-Slack URL" do
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://evil.example.com/slack.com",
      "actions" => [ { "action_id" => "unknown" } ]
    }
    @http.expects(:post).never

    SlackInteractionJob.perform_now(payload)
  end

  test "doesn't handle the click again when only the reply failed" do
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://hooks.slack.com/actions/T1/123/abc",
      "actions" => [ { "action_id" => "unknown" } ]
    }
    @http.expects(:post).raises(Faraday::ConnectionFailed, "down")

    assert_no_enqueued_jobs(only: SlackInteractionJob) do
      SlackInteractionJob.perform_now(payload)
    end
  end

  test "a click Slack delivers twice is handled once" do
    standup = standups(:daily)
    payload = {
      "type" => "block_actions",
      "user" => { "id" => @participant.platform_user_id },
      "response_url" => "https://hooks.slack.com/actions/T1/123/abc",
      "actions" => [ { "action_id" => "standup_selection", "action_ts" => "1800000000.000100", "selected_option" => { "value" => standup.id.to_s } } ]
    }
    @http.expects(:post).once

    assert_enqueued_jobs 1, only: StandupCollectionJob do
      2.times { SlackInteractionJob.perform_now(payload) }
    end
  end
end

require "test_helper"

class StandupMessageJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @participant = standup_participants(:one)
    @participant.update!(
      active: true,
      vacation_until: nil,
      cached_timezone: "UTC",
      cached_timezone_updated_at: Time.current
    )
    @platform_user_id = @participant.platform_user_id
    StandupResponse.where(platform_user_id: @platform_user_id, standup_id: @standup.id).delete_all

    @mock_slack_client = stub_slack_client
    @mock_slack_client.stubs(:get_user_info).returns(
      { "name" => "mrecachinas", "profile" => { "display_name" => "", "real_name" => "Michael Recachinas" } }
    )

    # Setup test data
    @standup.questions = [ "What did you do yesterday?", "What are you doing today?", "Any blockers?" ]
    @standup.intro = "Time for standup!"
    @standup.save!

    # Mock response from Slack
    @message_response = { "channel" => "D12345", "ts" => "1234567890.123456" }
  end

  test "sends standup message to slack user" do
    # Expect the message to be sent to Slack
    @mock_slack_client.expects(:send_message)
      .with(@platform_user_id, is_a(String), is_a(Array))
      .returns(@message_response)

    # Verify that a standup response is created
    assert_difference "StandupResponse.count", 1 do
      StandupMessageJob.perform_now(@platform_user_id, @standup.id)
    end

    # Verify the created standup response
    response = StandupResponse.last
    assert_equal @platform_user_id, response.platform_user_id
    assert_equal @standup.id, response.standup_id
    assert_equal "pending", response.status
    assert_equal @message_response["channel"], response.dm_channel
    assert_equal Time.zone.today, response.standup_date
    assert_empty response.answers
  end

  test "opens with a greeting that names the standup and channel, then the first question" do
    @standup.update!(platform_channel: "C0123ABC", intro: "Please share what you've been working on.")
    sent = nil
    @mock_slack_client.expects(:send_message)
      .with { |*args| sent = args; true }
      .returns(@message_response)

    StandupMessageJob.perform_now(@platform_user_id, @standup.id)

    _user_id, fallback, blocks = sent
    # The first name comes from the participant's stored name ("John Doe"), not a profile lookup.
    greeting = "Hi John! 👋 It's time for *Daily Standup* in <#C0123ABC>. Please share what you've been working on."
    assert_equal "Starting *Daily Standup* · 3 questions · Reply `skip` to pass on one\n\n#{greeting}\n\n*What did you do yesterday?*", fallback
    assert_equal %w[context divider section section], blocks.map { |block| block[:type] }
    assert_equal "Starting *Daily Standup* · 3 questions · Reply `skip` to pass on one", blocks.first[:elements].first[:text]
    assert_equal greeting, blocks.third.dig(:text, :text)
    assert_equal "*What did you do yesterday?*", blocks.fourth.dig(:text, :text)
    # The "Not today?" menu names this run, so it can't act on a later one.
    date = @participant.standup_date_for(Time.current).iso8601
    assert_equal "skip:#{@standup.id}:#{date}", blocks.third.dig(:accessory, :options).first[:value]
  end

  test "says so when it wraps up an unfinished run from an earlier day" do
    StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "pending",
      standup_date: Date.new(2025, 4, 6),
      answers: []
    )
    sent = nil
    @mock_slack_client.expects(:send_message)
      .with { |*args| sent = args; true }
      .returns(@message_response)

    StandupMessageJob.perform_now(@platform_user_id, @standup.id, "2025-04-07")

    assert_equal "⏰ Your previous *Daily Standup* wasn't finished, so I've wrapped it up.", sent.third.first.dig(:text, :text)
    assert_equal "skipped", StandupResponse.find_by(standup_date: Date.new(2025, 4, 6), platform_user_id: @platform_user_id).status
  end

  test "restart replaces a skipped run for the same day" do
    StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "skipped",
      standup_date: Date.new(2025, 4, 7),
      answers: [ { "question" => "What did you do yesterday?", "answer" => "(skipped)" } ]
    )
    @mock_slack_client.expects(:send_message).returns(@message_response)

    StandupMessageJob.perform_now(@platform_user_id, @standup.id, "2025-04-07", restart: true)

    response = StandupResponse.find_by!(platform_user_id: @platform_user_id, standup_id: @standup.id, standup_date: Date.new(2025, 4, 7))
    assert_equal "pending", response.status
    assert_empty response.answers
  end

  test "restart leaves a completed run alone" do
    StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "completed",
      standup_date: Date.new(2025, 4, 7),
      answers: []
    )
    @mock_slack_client.expects(:send_message).never

    assert_no_difference "StandupResponse.count" do
      StandupMessageJob.perform_now(@platform_user_id, @standup.id, "2025-04-07", restart: true)
    end
  end

  test "silently discards job when standup not found" do
    # With discard_on ActiveRecord::RecordNotFound, the job should
    # complete without raising when the standup doesn't exist
    assert_nothing_raised do
      StandupMessageJob.perform_now(@platform_user_id, 999999)
    end
  end

  test "handles slack client errors" do
    # Set up the expectation that send_message will be called and raise an error
    @mock_slack_client.expects(:send_message)
      .with(@platform_user_id, is_a(String), is_a(Array))
      .raises(StandardError.new("Slack API Error"))
      .once  # Explicitly state we expect this to be called only once

    # Verify no standup response is created when an error occurs
    assert_no_difference "StandupResponse.count" do
      assert_raises(StandardError) do
        StandupMessageJob.perform_now(@platform_user_id, @standup.id)
      end
    end
  end

  test "cancels previous pending responses before creating new one" do
    # Create a previous pending response
    StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "pending",
      answers: [ { "question" => "Test", "answer" => "Test answer", "timestamp" => Time.current } ],
      created_at: 1.day.ago
    )

    standup_date = Date.new(2025, 4, 7)

    # Expect the cancel method to be called
    StandupResponseService.expects(:cancel_previous_pending_responses)
      .with(@platform_user_id, @standup.id, standup_date)
      .once

    # Expect the message to be sent to Slack
    @mock_slack_client.expects(:send_message)
      .with(@platform_user_id, is_a(String), is_a(Array))
      .returns(@message_response)

    # Perform the job
    StandupMessageJob.perform_now(@platform_user_id, @standup.id, standup_date.iso8601)
  end

  test "does not send duplicate standup for same standup date" do
    StandupResponse.create!(
      platform_user_id: @platform_user_id,
      standup_id: @standup.id,
      status: "pending",
      standup_date: Date.new(2025, 4, 7),
      answers: []
    )

    @mock_slack_client.expects(:send_message).never

    assert_no_difference "StandupResponse.count" do
      StandupMessageJob.perform_now(@platform_user_id, @standup.id, "2025-04-07")
    end
  end

  test "does not send when schedule exception cancels the standup date" do
    standup_date = Date.new(2026, 5, 1)
    @standup.standup_schedule_exceptions.create!(
      exception_type: "cancelled",
      original_date: standup_date,
      reason: "One-off cancellation"
    )

    @mock_slack_client.expects(:send_message).never

    assert_no_difference "StandupResponse.count" do
      StandupMessageJob.perform_now(@platform_user_id, @standup.id, standup_date.iso8601)
    end
  end

  test "notes when the first question reached the person, by Slack's clock" do
    @mock_slack_client.expects(:send_message).returns({ "channel" => "D12345", "ts" => "1800000000.000100" })

    StandupMessageJob.perform_now(@platform_user_id, @standup.id)

    response = StandupResponse.find_by!(platform_user_id: @platform_user_id, standup: @standup)
    assert_equal "D12345", response.dm_channel
    assert_equal Time.zone.at(1_800_000_000.0001r), response.prompted_at
  end

  test "a failed first message leaves no run behind, so the retry sends it" do
    @mock_slack_client.expects(:send_message).raises(Faraday::ConnectionFailed, "down")

    assert_enqueued_with(job: StandupMessageJob) do
      StandupMessageJob.perform_now(@platform_user_id, @standup.id)
    end
    assert_not StandupResponse.exists?(platform_user_id: @platform_user_id, standup: @standup)
  end
end

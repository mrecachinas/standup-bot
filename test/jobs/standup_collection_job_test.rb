require "test_helper"

class StandupCollectionJobTest < ActiveJob::TestCase
  setup do
    @standup = standups(:daily)
    @mock_slack_client = mock("SlackClient")
    StandupCollectionJob.any_instance.stubs(:slack_client).returns(@mock_slack_client)
  end

  test "sends no-responses message when no completed responses exist today" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      @mock_slack_client.expects(:send_message).with(
        @standup.slack_channel,
        "No standup responses have been submitted today for #{@standup.name}."
      )

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "collects completed responses and posts summary" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: "U123456",
        status: "completed",
        answers: [
          { "question" => "What did you do yesterday?", "answer" => "Fixed bugs", "timestamp" => Time.current },
          { "question" => "What are you doing today?", "answer" => "Adding features", "timestamp" => Time.current }
        ]
      )

      @mock_slack_client.expects(:get_user_info).with("U123456").returns(
        { "name" => "johndoe", "profile" => { "display_name" => "John Doe" } }
      )

      @mock_slack_client.expects(:send_standup_summary).with(
        @standup.slack_channel,
        is_a(String),
        @standup.outro
      )

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "collects responses for explicit participant timezone date" do
    StandupResponse.where(standup: @standup).delete_all
    response_time = Time.new(2025, 4, 6, 20, 0, 0, "+00:00")
    StandupResponse.create!(
      standup: @standup,
      slack_id: "ULOCAL",
      status: "completed",
      standup_date: Date.new(2025, 4, 6),
      answers: [ { "question" => "Q?", "answer" => "A", "timestamp" => response_time } ],
      created_at: response_time
    )

    @mock_slack_client.expects(:get_user_info).with("ULOCAL").returns({ "name" => "local_user" })
    @mock_slack_client.expects(:send_standup_summary).with do |_channel, summary, _outro|
      summary.include?("local_user")
    end

    StandupCollectionJob.perform_now(@standup.id, "2025-04-06", "America/Los_Angeles")
  end

  test "aggregates multiple user responses with separator" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UAAA",
        status: "completed",
        answers: [ { "question" => "What did you do yesterday?", "answer" => "Task A", "timestamp" => Time.current } ]
      )
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UBBB",
        status: "completed",
        answers: [ { "question" => "What did you do yesterday?", "answer" => "Task B", "timestamp" => Time.current } ]
      )

      @mock_slack_client.expects(:get_user_info).with("UAAA").returns({ "name" => "alice" })
      @mock_slack_client.expects(:get_user_info).with("UBBB").returns({ "name" => "bob" })

      @mock_slack_client.expects(:send_standup_summary).with do |channel, summary, outro|
        channel == @standup.slack_channel &&
          summary.include?("alice") &&
          summary.include?("bob") &&
          summary.include?("---")
      end

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "excludes responses where all answers are skipped" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      # One user with all skipped answers
      StandupResponse.create!(
        standup: @standup,
        slack_id: "USKIP",
        status: "completed",
        answers: [
          { "question" => "Q1?", "answer" => "(skipped)", "timestamp" => Time.current },
          { "question" => "Q2?", "answer" => "(skipped)", "timestamp" => Time.current }
        ]
      )
      # Another user with real answers
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UREAL",
        status: "completed",
        answers: [ { "question" => "Q1?", "answer" => "Did stuff", "timestamp" => Time.current } ]
      )

      @mock_slack_client.expects(:get_user_info).with("USKIP").returns({ "name" => "skipper" })
      @mock_slack_client.expects(:get_user_info).with("UREAL").returns({ "name" => "worker" })

      @mock_slack_client.expects(:send_standup_summary).with do |_channel, summary, _outro|
        summary.include?("worker") && !summary.include?("skipper")
      end

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "falls back to name when display_name is missing" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UNODISPLAY",
        status: "completed",
        answers: [ { "question" => "Q?", "answer" => "A", "timestamp" => Time.current } ]
      )

      @mock_slack_client.expects(:get_user_info).with("UNODISPLAY").returns(
        { "name" => "fallback_name", "profile" => {} }
      )

      @mock_slack_client.expects(:send_standup_summary).with do |_channel, summary, _outro|
        summary.include?("fallback_name")
      end

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "falls back to Unknown User when user info is nil" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: "UGHOST",
        status: "completed",
        answers: [ { "question" => "Q?", "answer" => "A", "timestamp" => Time.current } ]
      )

      @mock_slack_client.expects(:get_user_info).with("UGHOST").returns(nil)

      @mock_slack_client.expects(:send_standup_summary).with do |_channel, summary, _outro|
        summary.include?("Unknown User")
      end

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "updates report generation history and delivers configured recipient copies" do
    generation = ReportGeneration.create!(
      standup: @standup,
      report_configuration: report_configurations(:daily_report),
      actor: users(:manager),
      status: "queued",
      delivery_channel: "reports-channel",
      recipients: [ "URECIP1" ],
      report_format: "slack",
      detail_level: "detailed",
      standup_date: Date.new(2025, 4, 7),
      timezone: "UTC",
      requested_at: Time.zone.parse("2025-04-07 12:00:00")
    )
    StandupResponse.create!(
      standup: @standup,
      slack_id: "UREPORT",
      status: "completed",
      standup_date: Date.new(2025, 4, 7),
      answers: [ { "question" => "Q?", "answer" => "Report answer", "timestamp" => Time.current } ]
    )

    @mock_slack_client.expects(:get_user_info).with("UREPORT").returns({ "name" => "reporter" })
    @mock_slack_client.expects(:send_standup_summary).with("reports-channel", includes("reporter"), @standup.outro)
    @mock_slack_client.expects(:send_message).with("URECIP1", includes("Report answer"))

    StandupCollectionJob.perform_now(
      @standup.id,
      "2025-04-07",
      "UTC",
      generation.id,
      {
        "destination_channel" => "reports-channel",
        "recipients" => [ "URECIP1" ],
        "report_format" => "slack",
        "detail_level" => "detailed"
      }
    )

    generation.reload
    assert generation.succeeded?
    assert generation.started_at.present?
    assert generation.completed_at.present?
    assert_equal 1, generation.metadata["response_count"]
    assert_equal 2, generation.metadata["delivery_count"]
  end

  test "summary detail level sends compact plain text report" do
    generation = ReportGeneration.create!(
      standup: @standup,
      actor: users(:manager),
      status: "queued",
      delivery_channel: "summary-channel",
      recipients: [],
      report_format: "plain_text",
      detail_level: "summary",
      standup_date: Date.new(2025, 4, 7),
      timezone: "UTC",
      requested_at: Time.zone.parse("2025-04-07 12:00:00")
    )
    StandupResponse.create!(
      standup: @standup,
      slack_id: "USUMMARY",
      status: "completed",
      standup_date: Date.new(2025, 4, 7),
      answers: [ { "question" => "Q?", "answer" => "Compact answer", "timestamp" => Time.current } ]
    )

    @mock_slack_client.expects(:get_user_info).with("USUMMARY").returns({ "name" => "summary_user" })
    @mock_slack_client.expects(:send_message).with do |channel, text|
      channel == "summary-channel" &&
        text.include?("1 completed response") &&
        text.include?("summary_user: 1 answer")
    end
    @mock_slack_client.expects(:send_standup_summary).never

    StandupCollectionJob.perform_now(
      @standup.id,
      "2025-04-07",
      "UTC",
      generation.id,
      {
        "destination_channel" => "summary-channel",
        "report_format" => "plain_text",
        "detail_level" => "summary"
      }
    )

    assert generation.reload.succeeded?
  end

  test "marks report generation failed when Slack delivery raises" do
    generation = ReportGeneration.create!(
      standup: @standup,
      actor: users(:manager),
      status: "queued",
      delivery_channel: "broken-channel",
      recipients: [],
      report_format: "slack",
      detail_level: "detailed",
      standup_date: Date.new(2025, 4, 7),
      timezone: "UTC",
      requested_at: Time.zone.parse("2025-04-07 12:00:00")
    )

    @mock_slack_client.expects(:send_message).with(
      "broken-channel",
      "No standup responses have been submitted today for #{@standup.name}."
    ).raises(StandardError.new("Slack unavailable"))

    assert_raises StandardError do
      StandupCollectionJob.perform_now(
        @standup.id,
        "2025-04-07",
        "UTC",
        generation.id,
        { "destination_channel" => "broken-channel" }
      )
    end

    generation.reload
    assert generation.failed?
    assert_includes generation.error_message, "Slack unavailable"
    assert_equal "StandardError", generation.metadata["error_class"]
  end

  test "ignores pending and skipped responses" do
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      StandupResponse.create!(standup: @standup, slack_id: "UPEND", status: "pending", answers: [])
      StandupResponse.create!(standup: @standup, slack_id: "USKIP", status: "skipped", answers: [])

      @mock_slack_client.expects(:send_message).with(
        @standup.slack_channel,
        "No standup responses have been submitted today for #{@standup.name}."
      )

      StandupCollectionJob.perform_now(@standup.id)
    end
  end

  test "silently discards job when standup not found" do
    assert_nothing_raised do
      StandupCollectionJob.perform_now(999999)
    end
  end
end

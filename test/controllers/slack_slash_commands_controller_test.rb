require "test_helper"

class SlackSlashCommandsControllerTest < ActionDispatch::IntegrationTest
  setup do
    SlackSlashCommandsController.any_instance.stubs(:verify_slack_request).returns(true)
    @participant = standup_participants(:one)
    @standup = @participant.standup
    @participant.update!(cached_timezone: "UTC", cached_timezone_updated_at: Time.current)
    StandupResponse.where(slack_id: @participant.slack_id).delete_all
  end

  test "standup start enqueues a manual standup" do
    standup_date = @participant.standup_date_for(Time.current).iso8601

    assert_enqueued_with(job: StandupMessageJob, args: [ @participant.slack_id, @standup.id, standup_date ]) do
      post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "start" }
    end

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "ephemeral", response_body["response_type"]
    assert_match(/Starting/, response_body["text"])
  end

  test "standup status reports pending progress" do
    StandupResponse.create!(
      standup: @standup,
      slack_id: @participant.slack_id,
      status: "pending",
      answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ]
    )

    post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "status" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_match(/in progress \(1\/#{@standup.questions.size}/, response_body["text"])
  end

  test "standup status uses participant timezone date" do
    @participant.update!(cached_timezone: "America/Los_Angeles", cached_timezone_updated_at: Time.current)

    Timecop.freeze(Time.new(2025, 4, 7, 6, 30, 0, "+00:00")) do
      StandupResponse.create!(
        standup: @standup,
        slack_id: @participant.slack_id,
        status: "pending",
        standup_date: Date.new(2025, 4, 6),
        answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ]
      )

      post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "status" }

      assert_response :success
      response_body = JSON.parse(response.body)
      assert_match(/in progress \(1\/#{@standup.questions.size}/, response_body["text"])
    end
  end

  test "standup-status command reports status" do
    post slack_standup_status_command_url, params: { user_id: @participant.slack_id }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_match(/Standup status/, response_body["text"])
  end

  test "standup skip marks pending responses skipped" do
    response = StandupResponse.create!(
      standup: @standup,
      slack_id: @participant.slack_id,
      status: "pending",
      answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ]
    )

    post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "skip" }

    assert_response :success
    assert_equal "skipped", response.reload.status
    assert_equal @standup.questions.size, response.answers.size
  end

  test "standup skip uses participant timezone date" do
    @participant.update!(cached_timezone: "America/Los_Angeles", cached_timezone_updated_at: Time.current)

    Timecop.freeze(Time.new(2025, 4, 7, 6, 30, 0, "+00:00")) do
      response = StandupResponse.create!(
        standup: @standup,
        slack_id: @participant.slack_id,
        status: "pending",
        standup_date: Date.new(2025, 4, 6),
        answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ]
      )

      post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "skip" }

      assert_response :success
      assert_equal "skipped", response.reload.status
    end
  end

  test "standup report enqueues collection job" do
    standup_date = @participant.standup_date_for(Time.current).iso8601

    assert_enqueued_with(job: StandupCollectionJob, args: [ @standup.id, standup_date, "Etc/UTC" ]) do
      post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "report" }
    end

    assert_response :success
  end

  test "standup history returns recent responses" do
    StandupResponse.create!(
      standup: @standup,
      slack_id: @participant.slack_id,
      status: "completed",
      answers: [ { "question" => @standup.questions.first, "answer" => "Done", "timestamp" => Time.current } ],
      created_at: Time.current
    )

    post slack_standup_command_url, params: { user_id: @participant.slack_id, text: "history 30" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_match(/Recent standups/, response_body["text"])
  end
end

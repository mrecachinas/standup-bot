require "test_helper"

class StandupResponseServiceTest < ActiveSupport::TestCase
  setup do
    @mock_slack_client = stub_slack_client

    # Setup a test standup with questions
    @standup = Standup.new(
      id: 1,
      name: "Test Standup",
      platform_channel: "general",
      questions: [ "What did you work on yesterday?", "What are you working on today?", "Any blockers?" ],
      intro: "Time for standup!",
      outro: "Thanks for your update!"
    )

    # Setup a test standup response
    @standup_response = StandupResponse.new(
      id: 1,
      standup_id: @standup.id,
      platform_user_id: "U12345",
      status: "pending",
      answers: []
    )

    @standup_response.stubs(:standup).returns(@standup)
  end

  test "record_answer adds an answer to the response" do
    answer_text = "I worked on feature X"

    # Expect the next question to be sent
    @mock_slack_client.expects(:send_message).with("U12345", includes(@standup.questions.second)).once

    StandupResponseService.record_answer(@standup_response, answer_text)

    # Verify the answer was added
    assert_equal 1, @standup_response.answers.size
    assert_equal answer_text, @standup_response.answers.first["answer"]
    assert_equal @standup.questions.first, @standup_response.answers.first["question"]
    assert_not_nil @standup_response.answers.first["timestamp"]
  end

  test "record_answer truncates oversized answers" do
    answer_text = "a" * (StandupResponse::MAX_ANSWER_LENGTH + 1)

    @mock_slack_client.expects(:send_message).once

    StandupResponseService.record_answer(@standup_response, answer_text)

    assert_equal StandupResponse::MAX_ANSWER_LENGTH, @standup_response.answers.first["answer"].length
  end

  test "skip_question marks a question as skipped" do
    # Expect the next question to be sent
    @mock_slack_client.expects(:send_message).once

    StandupResponseService.skip_question(@standup_response)

    # Verify the answer was added as skipped
    assert_equal 1, @standup_response.answers.size
    assert_equal "(skipped)", @standup_response.answers.first["answer"]
    assert_equal @standup.questions.first, @standup_response.answers.first["question"]
    assert_not @standup_response.answers.first.key?("message_id")
  end

  test "record_answer and skip_question keep the participant's message ID" do
    @mock_slack_client.stubs(:send_message)

    StandupResponseService.record_answer(@standup_response, "Shipped", message_id: "1700.1")
    StandupResponseService.record_answer(@standup_response, "skip", message_id: "1700.2")

    assert_equal [ [ "Shipped", "1700.1" ], [ "(skipped)", "1700.2" ] ],
      @standup_response.answers.map { |answer| [ answer["answer"], answer["message_id"] ] }
  end

  test "record_answer completes the standup when all questions are answered" do
    # Mock the response to already have two answers
    @standup_response.answers = [
      {
        question: @standup.questions[0],
        answer: "Answer 1",
        timestamp: Time.current
      },
      {
        question: @standup.questions[1],
        answer: "Answer 2",
        timestamp: Time.current
      }
    ]

    # This will be the final answer
    answer_text = "No blockers"

    # Expect get_user_info call, which is used when completing the standup
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "tz" => "America/New_York" }
    ).at_least_once

    # Expect completion message and posting to channel
    @mock_slack_client.expects(:send_message).at_least_once

    # Expect the status to change to completed
    @standup_response.expects(:status=).with("completed")

    StandupResponseService.record_answer(@standup_response, answer_text)

    # Verify the final answer was added
    assert_equal 3, @standup_response.answers.size
    assert_equal answer_text, @standup_response.answers.last["answer"]
    assert_equal @standup.questions.last, @standup_response.answers.last["question"]
  end

  test "repost_response updates an existing message in channel" do
    # Create a response with a stored message timestamp
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      platform_user_id: "U12345",
      status: "completed",
      answers: [
        {
          "question" => "What did you work on yesterday?",
          "answer" => "I worked on feature X",
          "timestamp" => Time.current
        },
        {
          "question" => "What are you working on today?",
          "answer" => "I will work on feature Y",
          "timestamp" => Time.current
        }
      ],
      platform_message_id: "1234567890.123456"
    )

    completed_response.stubs(:standup).returns(@standup)

    # Expect get_user_info call for display name
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "profile" => { "display_name" => "Test User" } }
    ).once

    # Expect update_message call with appropriate parameters
    @mock_slack_client.expects(:update_message).with(
      @standup.platform_channel,
      "1234567890.123456",
      includes("*What did you work on yesterday?*\nI worked on feature X"),
      [ { type: "section", text: { type: "mrkdwn", text: "*Test User* posted an update for *#{@standup.name}*" } } ],
      has_entry(:attachments, is_a(Array))
    ).returns({ "ok" => true })

    StandupResponseService.repost_response(completed_response)
  end

  test "repost_response posts new message when no timestamp exists" do
    # Create a response without a stored message timestamp
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      platform_user_id: "U12345",
      status: "completed",
      answers: [
        {
          "question" => "What did you work on yesterday?",
          "answer" => "I worked on feature X",
          "timestamp" => Time.current
        },
        {
          "question" => "What are you working on today?",
          "answer" => "I will work on feature Y",
          "timestamp" => Time.current
        }
      ],
      platform_message_id: nil # No stored timestamp
    )

    completed_response.stubs(:standup).returns(@standup)

    # Expect get_user_info call for display name
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "profile" => { "display_name" => "Test User" } }
    ).at_least_once

    # Expect send_message call instead of update_message
    @mock_slack_client.expects(:send_message).returns({ "ok" => true, "ts" => "1234567890.123456" })

    # Should try to save the new timestamp
    completed_response.expects(:save!).at_least_once

    StandupResponseService.repost_response(completed_response)
  end

  test "repost_response replaces a posted update with a skipped note when nothing is left to show" do
    # Create a response with only skipped answers
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      platform_user_id: "U12345",
      status: "completed",
      answers: [
        {
          "question" => "What did you work on yesterday?",
          "answer" => "(skipped)",
          "timestamp" => Time.current
        },
        {
          "question" => "What are you working on today?",
          "answer" => "(skipped)",
          "timestamp" => Time.current
        }
      ],
      platform_message_id: "1234567890.123456"
    )

    completed_response.stubs(:standup).returns(@standup)

    # Expect get_user_info call for display name
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "profile" => { "display_name" => "Test User" } }
    ).once

    # Retracted answers mustn't stay up in the channel.
    @mock_slack_client.expects(:update_message).with(
      @standup.platform_channel,
      "1234567890.123456",
      "*Test User* skipped *#{@standup.name}*",
      [ { type: "section", text: { type: "mrkdwn", text: "*Test User* skipped *#{@standup.name}*" } } ],
      attachments: []
    ).returns({ "ok" => true })

    StandupResponseService.repost_response(completed_response)
  end

  test "repost_response doesn't post a new update when every answer is skipped" do
    response = StandupResponse.new(standup_id: @standup.id, platform_user_id: "U12345", status: "completed",
      answers: [ { "question" => "Q1", "answer" => "(skipped)", "timestamp" => Time.current } ])
    response.stubs(:standup).returns(@standup)
    @mock_slack_client.stubs(:get_user_info).returns({ "name" => "Test User" })
    @mock_slack_client.expects(:send_message).never

    StandupResponseService.repost_response(response)
  end

  def completed_response_for_edit!
    participant = standup_participants(:one)
    ChatPlatform::SlackAdapter.any_instance.stubs(:display_name_for).returns("John Doe")
    StandupResponse.create!(
      standup: participant.standup, platform_user_id: participant.platform_user_id, status: "completed",
      standup_date: Date.current, platform_message_id: "post.1",
      answers: [
        { "question" => "Q1", "answer" => "Shipped", "timestamp" => 1.hour.ago, "message_id" => "100.1" },
        { "question" => "Q2", "answer" => "Reviewing", "timestamp" => 1.hour.ago, "message_id" => "100.2" }
      ]
    )
  end

  test "edit_answer updates the channel post and saves the new answer" do
    response = completed_response_for_edit!
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update).with(
      response.standup.platform_channel, "post.1",
      display_name: "John Doe", standup_name: response.standup.name,
      answers: [ { question: "Q1", answer: "Shipped" }, { question: "Q2", answer: "Pairing" } ],
      edited: true
    )

    assert StandupResponseService.edit_answer(response, 1, "Pairing")

    answers = response.reload.answers
    assert_equal [ "Shipped", "Pairing" ], answers.map { |answer| answer["answer"] }
    assert answers[1]["edited_at"].present?
    assert_nil answers[0]["edited_at"]
  end

  test "edit_answer keeps the original answer time after the run is finished" do
    response = completed_response_for_edit!
    answered_at = response.answers[1]["timestamp"]
    ChatPlatform::SlackAdapter.any_instance.stubs(:update_standup_update)

    StandupResponseService.edit_answer(response, 1, "Pairing")

    assert_equal answered_at, response.reload.answers[1]["timestamp"]
  end

  test "edit_answer on an unfinished run doesn't mark the answer edited" do
    response = completed_response_for_edit!
    response.update!(status: "pending", platform_message_id: nil)

    StandupResponseService.edit_answer(response, 1, "Pairing")

    assert_nil response.reload.answers[1]["edited_at"]
  end

  test "edit_answer keeps the old answer when the channel update fails, so a retry can apply the edit" do
    response = completed_response_for_edit!
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update)
      .raises(ChatPlatform::RateLimitedError.new("rate limited"))

    assert_raises(ChatPlatform::RateLimitedError) do
      StandupResponseService.edit_answer(response, 1, "skip")
    end
    assert_equal [ "Shipped", "Reviewing" ], response.reload.answers.map { |answer| answer["answer"] }

    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update).with(
      response.standup.platform_channel, "post.1",
      display_name: "John Doe", standup_name: response.standup.name,
      answers: [ { question: "Q1", answer: "Shipped" } ],
      edited: true
    )

    assert StandupResponseService.edit_answer(response, 1, "skip")
    assert_equal [ "Shipped", "(skipped)" ], response.reload.answers.map { |answer| answer["answer"] }
  end

  test "cancel_previous_pending_responses cancels old pending responses" do
    # Use Timecop to control time
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      # Create a real standup for testing
      test_standup = Standup.create!(
        name: "Test Cancel Standup",
        platform_channel: "general",
        questions: [ "Question 1", "Question 2" ],
        intro: "Test intro",
        outro: "Test outro"
      )

      # Create a pending response from yesterday
      yesterday_response = StandupResponse.create!(
        standup_id: test_standup.id,
        platform_user_id: "U12345",
        status: "pending",
        answers: [ { "question" => "Test", "answer" => "Test answer", "timestamp" => Time.current } ],
        created_at: 1.day.ago,
        standup_date: 1.day.ago.to_date
      )

      # Create a pending response from today (should not be canceled)
      today_response = StandupResponse.create!(
        standup_id: test_standup.id,
        platform_user_id: "U12345",
        status: "pending",
        answers: [],
        created_at: Time.current,
        standup_date: Time.zone.today
      )

      # Create a completed response from an earlier day (should not be canceled)
      completed_response = StandupResponse.create!(
        standup_id: test_standup.id,
        platform_user_id: "U12345",
        status: "completed",
        answers: [ { "question" => "Test", "answer" => "Test answer", "timestamp" => Time.current } ],
        created_at: 2.days.ago,
        standup_date: 2.days.ago.to_date
      )

      # Call the method
      StandupResponseService.cancel_previous_pending_responses("U12345", test_standup.id)

      # Verify results
      yesterday_response.reload
      today_response.reload
      completed_response.reload

      assert_equal "skipped", yesterday_response.status
      assert_equal "pending", today_response.status
      assert_equal "completed", completed_response.status
    end
  end

  test "cancel_previous_pending_responses handles no pending responses" do
    # Should not raise an error when there are no pending responses
    # Create a real standup for testing
    test_standup = Standup.create!(
      name: "Test No Pending Standup",
      platform_channel: "general",
      questions: [ "Question 1", "Question 2" ],
      intro: "Test intro",
      outro: "Test outro"
    )

    assert_nothing_raised do
      StandupResponseService.cancel_previous_pending_responses("U12345", test_standup.id)
    end
  end

  test "cancel_previous_pending_responses only affects specified user and standup" do
    # Use Timecop to control time
    Timecop.freeze(Time.new(2025, 4, 7, 12, 0, 0, "+00:00")) do
      # Create real standups for testing
      test_standup1 = Standup.create!(
        name: "Test User Standup 1",
        platform_channel: "general",
        questions: [ "Question 1", "Question 2" ],
        intro: "Test intro",
        outro: "Test outro"
      )

      test_standup2 = Standup.create!(
        name: "Test User Standup 2",
        platform_channel: "general",
        questions: [ "Question 1", "Question 2" ],
        intro: "Test intro",
        outro: "Test outro"
      )

      # Create pending responses for different users and standups
      user1_standup1 = StandupResponse.create!(
        standup_id: test_standup1.id,
        platform_user_id: "U12345",
        status: "pending",
        answers: [],
        created_at: 1.day.ago,
        standup_date: 1.day.ago.to_date
      )

      user2_standup1 = StandupResponse.create!(
        standup_id: test_standup1.id,
        platform_user_id: "U67890",
        status: "pending",
        answers: [],
        created_at: 1.day.ago,
        standup_date: 1.day.ago.to_date
      )

      user1_standup2 = StandupResponse.create!(
        standup_id: test_standup2.id,
        platform_user_id: "U12345",
        status: "pending",
        answers: [],
        created_at: 1.day.ago,
        standup_date: 1.day.ago.to_date
      )

      # Call the method for user1 and standup1
      StandupResponseService.cancel_previous_pending_responses("U12345", test_standup1.id)

      # Verify results
      user1_standup1.reload
      user2_standup1.reload
      user1_standup2.reload

      assert_equal "skipped", user1_standup1.status
      assert_equal "pending", user2_standup1.status
      assert_equal "pending", user1_standup2.status
    end
  end
end

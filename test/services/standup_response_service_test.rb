require "test_helper"

class StandupResponseServiceTest < ActiveSupport::TestCase
  setup do
    @mock_slack_client = mock("SlackClient")
    StandupResponseService.stubs(:slack_client).returns(@mock_slack_client)

    # Setup a test standup with questions
    @standup = Standup.new(
      id: 1,
      name: "Test Standup",
      slack_channel: "general",
      questions: [ "What did you work on yesterday?", "What are you working on today?", "Any blockers?" ],
      intro: "Time for standup!",
      outro: "Thanks for your update!"
    )

    # Setup a test standup response
    @standup_response = StandupResponse.new(
      id: 1,
      standup_id: @standup.id,
      slack_id: "U12345",
      status: "pending",
      answers: []
    )

    @standup_response.stubs(:standup).returns(@standup)
  end

  test "record_answer adds an answer to the response" do
    answer_text = "I worked on feature X"

    # Expect the next question to be sent
    @mock_slack_client.expects(:send_message).once

    StandupResponseService.record_answer(@standup_response, answer_text)

    # Verify the answer was added
    assert_equal 1, @standup_response.answers.size
    assert_equal answer_text, @standup_response.answers.first["answer"]
    assert_equal @standup.questions.first, @standup_response.answers.first["question"]
    assert_not_nil @standup_response.answers.first["timestamp"]
  end

  test "skip_question marks a question as skipped" do
    # Expect the next question to be sent
    @mock_slack_client.expects(:send_message).once

    StandupResponseService.skip_question(@standup_response)

    # Verify the answer was added as skipped
    assert_equal 1, @standup_response.answers.size
    assert_equal "(skipped)", @standup_response.answers.first["answer"]
    assert_equal @standup.questions.first, @standup_response.answers.first["question"]
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

  test "mark_completed manually completes a standup response" do
    # Expect get_user_info call, which is used when completing the standup
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "tz" => "America/New_York" }
    ).at_least_once

    # Expect completion message and posting to channel
    @mock_slack_client.expects(:send_message).at_least_once

    # Expect the status to change to completed
    @standup_response.expects(:status=).with("completed")
    @standup_response.expects(:save!)

    StandupResponseService.mark_completed(@standup_response)
  end

  test "process_answer_update sends the next question when more questions remain" do
    @standup_response.answers = [
      {
        question: @standup.questions[0],
        answer: "Answer 1",
        timestamp: Time.current
      }
    ]

    # Expect next question to be sent
    @mock_slack_client.expects(:send_message).with(
      @standup_response.slack_id,
      is_a(String)
    )

    @standup_response.expects(:save!)

    StandupResponseService.process_answer_update(@standup_response)
  end

  test "process_answer_update completes the standup when all questions are answered" do
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
      },
      {
        question: @standup.questions[2],
        answer: "Answer 3",
        timestamp: Time.current
      }
    ]

    # Expect get_user_info call, which is used when completing the standup
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "tz" => "America/New_York" }
    ).at_least_once

    # Expect completion message and posting to channel
    @mock_slack_client.expects(:send_message).at_least_once

    # Expect the status to change to completed
    @standup_response.expects(:status=).with("completed")
    @standup_response.expects(:save!)

    StandupResponseService.process_answer_update(@standup_response)
  end

  test "repost_response updates an existing message in channel" do
    # Create a response with a stored message timestamp
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      slack_id: "U12345",
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
      slack_message_ts: "1234567890.123456"
    )

    completed_response.stubs(:standup).returns(@standup)

    # Expect get_user_info call for display name
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "profile" => { "display_name" => "Test User" } }
    ).once

    # Expect update_message call with appropriate parameters
    @mock_slack_client.expects(:update_message).with(
      @standup.slack_channel,
      "1234567890.123456",
      is_a(String),
      is_a(Array)
    ).returns({ "ok" => true })

    StandupResponseService.repost_response(completed_response)
  end

  test "repost_response posts new message when no timestamp exists" do
    # Create a response without a stored message timestamp
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      slack_id: "U12345",
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
      slack_message_ts: nil # No stored timestamp
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

  test "repost_response handles empty answers" do
    # Create a response with only skipped answers
    completed_response = StandupResponse.new(
      id: 2,
      standup_id: @standup.id,
      slack_id: "U12345",
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
      slack_message_ts: "1234567890.123456"
    )

    completed_response.stubs(:standup).returns(@standup)

    # Expect get_user_info call for display name
    @mock_slack_client.expects(:get_user_info).with("U12345").returns(
      { "name" => "Test User", "profile" => { "display_name" => "Test User" } }
    ).once

    # With all skipped answers, there should be no update
    # because post_individual_response will return early with no updates
    # and repost_response will fall through to that method
    StandupResponseService.repost_response(completed_response)

    # Assert that the method completed successfully without updating the message
    # The mock expectations above ensure update_message was not called
    assert true, "repost_response should handle empty answers without calling update_message"
  end
end

require "test_helper"

class Manager::StandupResponsesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "manager views owned response history with completion status and answers" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_includes response.body, "Response history for #{@owned_standup.name}"
    assert_includes response.body, "View analytics"
    assert_includes response.body, manager_standup_analytics_path(@owned_standup)
    assert_includes response.body, "John Doe"
    assert_includes response.body, "Answered"
    assert_includes response.body, "Fixed bugs"
    assert_includes response.body, "Jane Smith"
    assert_includes response.body, "Pending"
  end

  test "date filter excludes responses outside selected range" do
    @owned_standup.standup_participants.create!(slack_id: "UDATE159", slack_name: "Date Filter User")
    StandupResponse.create!(
      standup: @owned_standup,
      slack_id: "UDATE159",
      status: "completed",
      answers: [ { "question" => "Any blockers?", "answer" => "Outside filter" } ],
      standup_date: Date.new(2025, 4, 5),
      created_at: Time.zone.local(2025, 4, 5, 9, 0, 0)
    )
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_not_includes response.body, "Outside filter"
  end

  test "participant filter limits displayed response contents" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06", participant: "U234567" }

    assert_response :success
    assert_includes response.body, "Jane Smith"
    assert_not_includes response.body, "Fixed bugs"
  end

  test "question filter limits displayed answers" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06", question: "Any blockers?" }

    assert_response :success
    assert_includes response.body, "None"
    assert_not_includes response.body, "Fixed bugs"
    assert_not_includes response.body, "Adding features"
  end

  test "manager cannot infer unowned response contents" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@unowned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :forbidden
    assert_not_includes response.body, "Complete project X"
  end

  test "admin can view response history for any standup" do
    sign_in(@admin, "admin-access-token")

    get manager_standup_responses_path(@unowned_standup),
      params: { start_date: "2025-04-06", end_date: "2025-04-06" }

    assert_response :success
    assert_includes response.body, "Alice Johnson"
    assert_includes response.body, "Complete project X"
    assert_includes response.body, "Answered"
  end

  test "response history displays timestamps and updated state" do
    @owned_standup.standup_participants.create!(slack_id: "UTIME159", slack_name: "Timestamp User")
    response_record = StandupResponse.create!(
      standup: @owned_standup,
      slack_id: "UTIME159",
      status: "completed",
      answers: [
        {
          "question" => "What did you do yesterday?",
          "answer" => "Added timestamp coverage",
          "timestamp" => "2025-04-08T09:05:00Z"
        }
      ],
      standup_date: Date.new(2025, 4, 8),
      created_at: Time.zone.local(2025, 4, 8, 9, 0, 0)
    )
    response_record.update_column(:updated_at, Time.zone.local(2025, 4, 8, 10, 30, 0))
    sign_in(@manager, "manager-access-token")

    get manager_standup_responses_path(@owned_standup),
      params: { start_date: "2025-04-08", end_date: "2025-04-08", participant: "UTIME159" }

    assert_response :success
    assert_includes response.body, "Submitted"
    assert_includes response.body, "Last updated"
    assert_includes response.body, "Updated after submission"
    assert_includes response.body, "Added timestamp coverage"
    assert_includes response.body, "Answered at"
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

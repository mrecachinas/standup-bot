require "test_helper"

class Api::ResponsesHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
  end

  test "manager views owned response history with completion status and answers" do
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2025-04-06", end_date: "2025-04-06")

    assert_response :success
    body = response.parsed_body
    assert_equal @owned_standup.name, body.dig("standup", "name")
    history = body["history"]
    assert_equal({ "start_date" => "2025-04-06", "end_date" => "2025-04-06", "participant" => nil, "question" => nil }, history["filters"])
    assert_not history["range_limited"]
    assert_equal 90, history["max_range_days"]
    assert_equal @owned_standup.questions, history["question_options"]
    assert_includes history["participant_options"].map { |option| option["label"] }, "John Doe (U123456)"

    day = history["days"].sole
    assert_equal "2025-04-06", day["date"]
    assert_equal "April 06, 2025", day["date_label"]
    entries = day["entries"].index_by { |entry| entry["display_name"] }

    john = entries.fetch("John Doe")
    assert_equal "Answered", john["status_label"]
    assert_equal "success", john["status_tone"]
    assert john["answered"]
    assert_equal [ "Fixed bugs", "Adding features", "None" ], john["answers"].map { |answer| answer["text"] }
    assert_equal "What did you do yesterday?", john["answers"].first["question"]
    assert_nil john["empty_message"]

    jane = entries.fetch("Jane Smith")
    assert_equal "Pending", jane["status_label"]
    assert_equal "info", jane["status_tone"]
    assert_equal "No submitted answers were recorded for this response.", jane["empty_message"]

    assert_equal day["answered_count"], history.dig("summary", "answered")
    assert_equal history["days"].size, history.dig("summary", "dates")
    summary = history["summary"]
    assert_equal summary["expected"], summary.values_at("answered", "skipped", "pending", "missed").sum
  end

  test "date filter excludes responses outside selected range" do
    @owned_standup.standup_participants.create!(platform_user_id: "UDATE159", display_name: "Date Filter User")
    StandupResponse.create!(
      standup: @owned_standup,
      platform_user_id: "UDATE159",
      status: "completed",
      answers: [ { "question" => "Any blockers?", "answer" => "Outside filter" } ],
      standup_date: Date.new(2025, 4, 5),
      created_at: Time.zone.local(2025, 4, 5, 9, 0, 0)
    )
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2025-04-06", end_date: "2025-04-06")

    assert_response :success
    assert_not_includes response.body, "Outside filter"
  end

  test "participant filter limits displayed response contents" do
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2025-04-06", end_date: "2025-04-06", participant: "U234567")

    assert_response :success
    assert_equal "U234567", response.parsed_body.dig("history", "filters", "participant")
    names = response.parsed_body.dig("history", "days").flat_map { |day| day["entries"].map { |entry| entry["display_name"] } }
    assert_equal [ "Jane Smith" ], names.uniq
    assert_not_includes response.body, "Fixed bugs"
  end

  test "question filter limits displayed answers" do
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2025-04-06", end_date: "2025-04-06", question: "Any blockers?")

    assert_response :success
    assert_includes response.body, "None"
    assert_not_includes response.body, "Fixed bugs"
    assert_not_includes response.body, "Adding features"
    jane = response.parsed_body.dig("history", "days").sole["entries"].find { |entry| entry["display_name"] == "Jane Smith" }
    assert_equal "No answer recorded for “Any blockers?”.", jane["empty_message"]
  end

  test "missed people are flagged" do
    Timecop.freeze(Time.zone.local(2025, 4, 8, 12, 0, 0)) do
      sign_in(@manager, "manager-access-token")
      get history_path(@owned_standup, start_date: "2025-04-07", end_date: "2025-04-07")
    end

    entry = response.parsed_body.dig("history", "days").sole["entries"].find { |row| row["display_name"] == "John Doe" }
    assert entry["missed"]
    assert_equal "Missed", entry["status_label"]
    assert_equal "warning", entry["status_tone"]
    assert_equal "No response submitted for this standup date.", entry["empty_message"]
  end

  test "long ranges are clamped" do
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2024-01-01", end_date: "2025-04-06")

    history = response.parsed_body["history"]
    assert history["range_limited"]
    assert_equal "2025-01-07", history.dig("filters", "start_date")
  end

  test "manager cannot infer unowned response contents" do
    sign_in(@manager, "manager-access-token")

    get history_path(@unowned_standup, start_date: "2025-04-06", end_date: "2025-04-06")

    assert_response :forbidden
    assert_not_includes response.body, "Complete project X"
  end

  test "admin can view response history for any standup" do
    sign_in(@admin, "admin-access-token")

    get history_path(@unowned_standup, start_date: "2025-04-06", end_date: "2025-04-06")

    assert_response :success
    assert_includes response.body, "Alice Johnson"
    assert_includes response.body, "Complete project X"
    assert_includes response.body, "Answered"
  end

  test "an admin's token can read history" do
    get api_standup_responses_path(@unowned_standup, view: "history", start_date: "2025-04-06", end_date: "2025-04-06"),
      headers: token_headers,
      as: :json

    assert_response :success
    assert_includes response.body, "Complete project X"
  end

  test "response history displays timestamps and updated state" do
    @owned_standup.standup_participants.create!(platform_user_id: "UTIME159", display_name: "Timestamp User", avatar_url: "https://avatars.slack-edge.com/time.png")
    response_record = StandupResponse.create!(
      standup: @owned_standup,
      platform_user_id: "UTIME159",
      status: "completed",
      answers: [ { "question" => "What did you do yesterday?", "answer" => "Added timestamp coverage", "timestamp" => "2025-04-08T09:05:00Z" } ],
      standup_date: Date.new(2025, 4, 8),
      created_at: Time.zone.local(2025, 4, 8, 9, 0, 0)
    )
    response_record.update_column(:updated_at, Time.zone.local(2025, 4, 8, 10, 30, 0))
    sign_in(@manager, "manager-access-token")

    get history_path(@owned_standup, start_date: "2025-04-08", end_date: "2025-04-08", participant: "UTIME159")

    assert_response :success
    entry = response.parsed_body.dig("history", "days").sole["entries"].sole
    assert_equal response_record.id, entry["response_id"]
    assert_equal "2025-04-08T09:00:00Z", entry["submitted_at"]
    assert_equal "2025-04-08T10:30:00Z", entry["updated_at"]
    assert entry["updated_after_create"]
    assert entry["submitted_at_label"].present?
    answer = entry["answers"].sole
    assert_equal "Added timestamp coverage", answer["text"]
    assert_equal "2025-04-08T09:05:00Z", answer["answered_at"]
    assert answer["answered_at_label"].present?
    assert_equal "https://avatars.slack-edge.com/time.png", entry["avatar_url"]
  end

  test "the admin list keeps its shape and filters" do
    sign_in(@manager, "manager-access-token")

    get api_standup_responses_path(@owned_standup, status: "completed", limit: 10), as: :json

    assert_response :success
    assert_equal [ "responses" ], response.parsed_body.keys
    assert response.parsed_body["responses"].all? { |row| row["status"] == "completed" }
    assert_equal %w[id standup_id platform_user_id dm_channel status answers answer_count platform_message_id created_at updated_at],
      response.parsed_body["responses"].first.keys
  end

  test "the admin list rejects invalid timestamps" do
    get api_standup_responses_path(@owned_standup, since: "2025-13-45"), headers: token_headers, as: :json

    assert_response :bad_request
    assert_match "Invalid timestamp", response.parsed_body["error"]
  end

  private

  def history_path(standup, **filters)
    api_standup_responses_path(standup, view: "history", **filters)
  end

  def token_headers
    { "Authorization" => "Bearer admin-access-token" }
  end

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :success
  end
end

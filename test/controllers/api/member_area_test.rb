require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::MemberAreaTest < ActionDispatch::IntegrationTest
  include TeamsTestHelper

  ADMIN_TOKEN = "admin-access-token".freeze

  setup do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret" })
    @daily = standups(:daily)
  end

  test "requires sign-in" do
    get api_me_standups_path, as: :json

    assert_response :unauthorized
  end

  test "an admin's token has no member identity" do
    headers = { "Authorization" => "Bearer #{ADMIN_TOKEN}" }

    get api_me_responses_path, headers: headers, as: :json
    assert_response :forbidden

    get api_me_availability_path, headers: headers, as: :json
    assert_response :forbidden

    patch api_me_availability_path, params: { away_until: (Date.current + 1).iso8601, standup_ids: [ @daily.id ] }, headers: headers, as: :json
    assert_response :forbidden
  end

  test "token-only managers aren't members" do
    post api_session_path, params: { email: users(:manager).email, access_token: "manager-access-token" }, as: :json

    get api_me_standups_path, as: :json

    assert_response :forbidden
    assert_equal "Sign in with Slack or Microsoft to see your own standups.", response.parsed_body["error"]
  end

  test "members see only their own standups" do
    sign_in_member("U345678")

    get api_me_standups_path, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "slack", body.dig("member", "platform")
    assert_equal "Slack", body.dig("member", "platform_label")
    assert_equal "U345678", body.dig("member", "platform_user_id")
    assert_equal [ standups(:weekly).id ], body["standups"].map { |summary| summary.dig("standup", "id") }
    assert_equal 1, body.dig("stats", "standups_count")
    assert_equal "Available", body.dig("stats", "status_label")

    summary = body["standups"].sole
    assert_equal UiFormat.schedule_summary(standups(:weekly)), summary.dig("standup", "schedule_summary")
    assert summary.key?("status_label")
    assert summary.key?("next_check_in")
    assert summary.key?("teammates")
  end

  test "members can't manage standups they don't own" do
    sign_in_member("U123456")

    get api_standup_path(@daily), as: :json

    assert_response :forbidden
  end

  test "members see their own answers, filtered by standup" do
    sign_in_member("U123456")

    get api_me_responses_path(standup_id: @daily.id), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal({ "id" => @daily.id, "name" => @daily.name }, body["standup"])
    assert_includes response.body, "Fixed bugs"
    assert_not_includes response.body, "Complete project X"
    completed = body["responses"].find { |entry| entry["status"] == "completed" }
    assert_equal "Answered", completed["status_label"]
    assert_equal "success", completed["status_tone"]
    assert_equal 30, body["limit"]
  end

  test "members can set and clear time away" do
    sign_in_member("U123456")
    participant = standup_participants(:one)

    get api_me_availability_path, as: :json
    assert_response :success
    assert_equal [ @daily.id ], response.parsed_body["standups"].map { |standup| standup["standup_id"] }
    assert_empty response.parsed_body["away"]

    patch api_me_availability_path, params: { away_until: (Date.current + 5).iso8601, standup_ids: [ @daily.id ] }, as: :json

    assert_response :success
    assert_equal "You're marked away through #{(Date.current + 5).strftime("%A, %B %-d")}.", response.parsed_body["notice"]
    assert_equal [ (Date.current + 5).iso8601 ], response.parsed_body["away"].map { |away| away["vacation_until"] }
    assert_equal Date.current + 5, participant.reload.vacation_until
    log = AuditLog.find_by!(action: "standup_participant.away", auditable: participant)
    assert_equal "Member U123456 (U123456)", log.actor_label

    get api_me_standups_path, as: :json
    assert_equal (Date.current + 5).iso8601, response.parsed_body["away_until"]
    assert_equal "Away", response.parsed_body.dig("stats", "status_label")

    delete clear_api_me_availability_path, as: :json

    assert_response :success
    assert_equal "Welcome back. You'll get your next check-ins as usual.", response.parsed_body["notice"]
    assert_nil participant.reload.vacation_until
    assert participant.active?
    assert AuditLog.exists?(action: "standup_participant.back", auditable: participant)
  end

  test "time away can't start in the past" do
    sign_in_member("U123456")

    patch api_me_availability_path, params: { away_until: (Date.current - 1).iso8601, standup_ids: [ @daily.id ] }, as: :json

    assert_response :unprocessable_entity
    assert_equal "The last day away can't be in the past.", response.parsed_body["error"]
    assert_nil standup_participants(:one).reload.vacation_until
  end

  test "members can't set time away on someone else's standup" do
    sign_in_member("U123456")

    patch api_me_availability_path, params: { away_until: (Date.current + 2).iso8601, standup_ids: [ standups(:weekly).id ] }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Choose at least one standup.", response.parsed_body["error"]
    assert_nil standup_participants(:three).reload.vacation_until
  end

  test "Teams members see their Teams standups" do
    enable_teams!
    standup = create_teams_standup!
    sign_in_teams_member

    get api_me_standups_path, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "teams", body.dig("member", "platform")
    assert_equal "Microsoft Teams", body.dig("member", "platform_label")
    assert_equal [ standup.id ], body["standups"].map { |summary| summary.dig("standup", "id") }
    assert_equal "Engineering › Standup", body["standups"].first.dig("standup", "platform_channel_name")

    get api_me_availability_path, as: :json
    assert_equal [ standup.id ], response.parsed_body["standups"].map { |entry| entry["standup_id"] }
  end

  private

  def sign_in_member(platform_user_id)
    get slack_sign_in_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    identity = User::Identity.new(user_id: platform_user_id, team_id: "T1", email: "#{platform_user_id.downcase}@example.com", email_verified: true, name: "Member #{platform_user_id}")
    SlackSignIn.any_instance.stubs(:identity_for).returns(identity)
    get slack_sign_in_callback_path, params: { code: "oauth-code", state: state }
    assert_response :see_other
  end

  def sign_in_teams_member
    get microsoft_sign_in_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    identity = User::Identity.new(user_id: TEAMS_USER_ID, name: "Tess Teams", email: nil, email_verified: false)
    MicrosoftSignIn.any_instance.stubs(:identity_for).returns(identity)
    get microsoft_sign_in_callback_path, params: { code: "code", state: state }
    assert_response :see_other
  end
end

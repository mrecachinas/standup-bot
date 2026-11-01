require "test_helper"

class Me::MemberAreaTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.stubs(:slack).returns({ client_id: "123.456", client_secret: "client-secret" })
    @daily = standups(:daily)
  end

  test "requires sign-in" do
    get me_root_path

    assert_redirected_to new_session_path
  end

  test "token-only managers are sent back to the console" do
    post session_path, params: { email: users(:manager).email, access_token: "manager-access-token" }

    get me_root_path

    assert_redirected_to manager_standups_path
  end

  test "members see only their own standups" do
    sign_in_member("U345678")

    get me_root_path

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(standups(:weekly), :member)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@daily, :member)}", count: 0
  end

  test "members can't manage standups they don't own" do
    sign_in_member("U123456")

    get manager_standup_path(@daily)

    assert_response :forbidden
  end

  test "members see their own answers, filtered by standup" do
    sign_in_member("U123456")

    get me_responses_path(standup_id: @daily.id)

    assert_response :success
    assert_includes response.body, "Fixed bugs"
    assert_not_includes response.body, "Complete project X"
  end

  test "members can set and clear time away" do
    sign_in_member("U123456")
    participant = standup_participants(:one)

    patch me_availability_path, params: { away_until: (Date.current + 5).iso8601, standup_ids: [ @daily.id ] }

    assert_redirected_to me_availability_path
    assert_equal Date.current + 5, participant.reload.vacation_until
    assert AuditLog.exists?(action: "standup_participant.away", auditable: participant)

    delete clear_me_availability_path

    assert_nil participant.reload.vacation_until
    assert participant.active?
  end

  test "time away can't start in the past" do
    sign_in_member("U123456")

    patch me_availability_path, params: { away_until: (Date.current - 1).iso8601, standup_ids: [ @daily.id ] }

    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t be in the past"
    assert_nil standup_participants(:one).reload.vacation_until
  end

  test "members can't set time away on someone else's standup" do
    sign_in_member("U123456")

    patch me_availability_path, params: { away_until: (Date.current + 2).iso8601, standup_ids: [ standups(:weekly).id ] }

    assert_response :unprocessable_entity
    assert_nil standup_participants(:three).reload.vacation_until
  end

  private

  def sign_in_member(slack_id)
    get slack_sign_in_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    identity = SlackSignIn::Identity.new(slack_id: slack_id, team_id: "T1", email: "#{slack_id.downcase}@example.com", email_verified: true, name: "Member #{slack_id}")
    SlackSignIn.any_instance.stubs(:identity_for).returns(identity)
    get slack_sign_in_callback_path, params: { code: "oauth-code", state: state }
    assert_redirected_to me_root_path
  end
end

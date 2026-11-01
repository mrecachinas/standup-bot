require "test_helper"
require_relative "../../support/teams_test_helper"

class Api::ReportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include TeamsTestHelper

  ADMIN_TOKEN = "admin-access-token".freeze

  setup do
    @manager = users(:manager)
    @admin = users(:admin)
    @owned_standup = standups(:daily)
    @unowned_standup = standups(:weekly)
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "requires authentication" do
    get api_standup_report_path(@owned_standup), as: :json

    assert_response :unauthorized
  end

  test "shows the configuration, options, hints, and recent failures" do
    sign_in(@manager, "manager-access-token")

    get api_standup_report_path(@owned_standup), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal @owned_standup.id, body.dig("standup", "id")
    configuration = body["report_configuration"]
    assert configuration["persisted"]
    assert_equal "daily-reports", configuration["delivery_channel"]
    assert_equal [ "UREPORT1" ], configuration["recipients"]
    assert_equal "UREPORT1", configuration["recipients_text"]
    assert_equal "Detailed Q&A", configuration["detail_level_label"]
    assert_equal ReportConfiguration::REPORT_FORMATS.keys, body.dig("options", "report_formats").map { |option| option["value"] }
    assert_equal ReportConfiguration::DETAIL_LEVELS.values, body.dig("options", "detail_levels").map { |option| option["label"] }
    assert_equal PlatformSerializer.copy_for(:slack, :recipients_hint), body.dig("copy", "recipients_hint")
    assert_equal "daily-standup or C0123", body.dig("copy", "delivery_channel_placeholder")

    failed = body["report_generations"].find { |generation| generation["failed"] }
    assert_equal "Failed", failed["status_label"]
    assert_equal "danger", failed["status_tone"]
    assert_equal "Slack API timeout", failed["error_message"]
    assert_equal "Slack API timeout", failed["result_label"]
    assert_equal "by #{@manager.name}", failed["requested_by_label"]
    assert_equal 30, body.dig("summary", "period_days")
  end

  test "a standup without settings gets defaults for its channel" do
    sign_in(@admin, "admin-access-token")

    get api_standup_report_path(@unowned_standup), as: :json

    assert_response :success
    configuration = response.parsed_body["report_configuration"]
    assert_not configuration["persisted"]
    assert_equal @unowned_standup.platform_channel, configuration["delivery_channel"]
    assert_equal "No one else", configuration["recipients_label"]
  end

  test "Teams standups get Teams recipient hints" do
    enable_teams!
    standup = create_teams_standup!
    standup.standup_ownerships.create!(user: @manager)
    sign_in(@manager, "manager-access-token")

    get api_standup_report_path(standup), as: :json

    assert_response :success
    copy = response.parsed_body["copy"]
    assert_equal PlatformSerializer.copy_for(:teams, :recipients_placeholder), copy["recipients_placeholder"]
    assert_equal PlatformSerializer.copy_for(:teams, :recipients_hint), copy["recipients_hint"]
    assert_equal PlatformSerializer.copy_for(:teams, :channel_id_placeholder), copy["delivery_channel_placeholder"]
    assert_equal TEAMS_CHANNEL, response.parsed_body.dig("report_configuration", "delivery_channel")
  end

  test "manager updates the configuration and writes an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'report.configuration.update').count", 1 do
      patch api_standup_report_path(@owned_standup),
        params: {
          report_configuration: {
            delivery_channel: "#new-reports",
            recipients_text: "URECIP1\n#leaders",
            report_format: "plain_text",
            detail_level: "summary"
          }
        },
        as: :json
    end

    assert_response :success
    assert_equal "Report settings saved.", response.parsed_body["notice"]
    assert_equal "new-reports", response.parsed_body.dig("report_configuration", "delivery_channel")
    configuration = @owned_standup.reload.report_configuration
    assert_equal "new-reports", configuration.delivery_channel
    assert_equal [ "URECIP1", "leaders" ], configuration.recipients
    assert_equal "plain_text", configuration.report_format
    assert_equal "summary", configuration.detail_level

    audit_log = AuditLog.where(action: "report.configuration.update").order(:created_at).last
    assert_equal @manager, audit_log.actor
    assert_equal @owned_standup, audit_log.auditable
    assert_equal [ "daily-reports", "new-reports" ], audit_log.metadata.dig("changes", "delivery_channel")
  end

  test "invalid configuration returns field errors without an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch api_standup_report_path(@owned_standup),
        params: {
          report_configuration: {
            delivery_channel: "bad channel",
            recipients_text: "bad recipient",
            report_format: "slack",
            detail_level: "detailed"
          }
        },
        as: :json
    end

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert body["errors"].any? { |message| message.include?("must be a Slack channel name or ID without spaces") }
    assert body["errors"].any? { |message| message.include?("bad recipient") }
    assert body["field_errors"].key?("delivery_channel")
    assert body["field_errors"].key?("recipients")
  end

  test "manager queues a manual report and writes an audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "ReportGeneration.count", 1 do
      assert_difference "AuditLog.where(action: 'report.manual_generation.queued').count", 1 do
        assert_enqueued_jobs 1 do
          post generate_api_standup_report_path(@owned_standup), as: :json
        end
      end
    end

    assert_response :success
    assert_equal "Report queued. It will appear in the history below when it's sent.", response.parsed_body["notice"]
    generation = ReportGeneration.recent.first
    assert_equal "queued", generation.status
    assert_equal @manager, generation.actor
    assert_equal "daily-reports", generation.delivery_channel
    assert_equal generation.id, response.parsed_body["report_generations"].first["id"]
  end

  test "a failed manual report is returned and audited" do
    report_configurations(:daily_report).update_column(:delivery_channel, "")
    sign_in(@manager, "manager-access-token")

    assert_difference "ReportGeneration.count", 1 do
      assert_difference "AuditLog.where(action: 'report.manual_generation.failure').count", 1 do
        assert_no_enqueued_jobs do
          post generate_api_standup_report_path(@owned_standup), as: :json
        end
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "Report configuration is invalid"
    assert ReportGeneration.recent.first.failed?
  end

  test "a bearer token queues a report and is audited as its user" do
    assert_difference "ReportGeneration.count", 1 do
      post generate_api_standup_report_path(@owned_standup), headers: token_headers, as: :json
    end

    assert_response :success
    assert_equal users(:admin), ReportGeneration.recent.first.actor
    log = AuditLog.where(action: "report.manual_generation.queued").order(:created_at).last
    assert_equal users(:admin), log.actor
    assert_equal "access_token", log.metadata["auth_method"]
  end

  test "manager can't configure or trigger reports for a standup they don't own" do
    sign_in(@manager, "manager-access-token")

    get api_standup_report_path(@unowned_standup), as: :json
    assert_response :forbidden

    assert_no_difference [ "ReportConfiguration.count", "ReportGeneration.count", "AuditLog.count" ] do
      patch api_standup_report_path(@unowned_standup),
        params: { report_configuration: { delivery_channel: "blocked", report_format: "slack", detail_level: "summary" } },
        as: :json
    end
    assert_response :forbidden

    assert_no_difference [ "ReportGeneration.count", "AuditLog.count" ] do
      post generate_api_standup_report_path(@unowned_standup), as: :json
    end
    assert_response :forbidden
  end

  test "admin can configure reports for any standup" do
    sign_in(@admin, "admin-access-token")

    assert_difference "ReportConfiguration.count", 1 do
      patch api_standup_report_path(@unowned_standup),
        params: { report_configuration: { delivery_channel: "weekly-reports", report_format: "slack", detail_level: "summary" } },
        as: :json
    end

    assert_response :success
    assert_equal "weekly-reports", @unowned_standup.reload.report_configuration.delivery_channel
  end

  private

  def token_headers
    { "Authorization" => "Bearer #{ADMIN_TOKEN}" }
  end

  def sign_in(user, access_token)
    post api_session_path, params: { email: user.email, access_token: access_token }, as: :json
    assert_response :created
  end
end

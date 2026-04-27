require "test_helper"

class Manager::StandupReportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    get manager_standup_report_path(@owned_standup)

    assert_redirected_to new_session_path
  end

  test "shows configuration form and recent failures" do
    sign_in(@manager, "manager-access-token")

    get manager_standup_report_path(@owned_standup)

    assert_response :success
    assert_includes response.body, "Report configuration"
    assert_includes response.body, "Generate report now"
    assert_includes response.body, "Slack API timeout"
    assert_includes response.body, "Failed"
  end

  test "manager updates report configuration and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "AuditLog.where(action: 'report.configuration.update').count", 1 do
      patch manager_standup_report_path(@owned_standup),
        params: {
          report_configuration: {
            delivery_channel: "#new-reports",
            recipients_text: "URECIP1\n#leaders",
            report_format: "plain_text",
            detail_level: "summary"
          }
        }
    end

    assert_redirected_to manager_standup_report_path(@owned_standup, config_updated: "1")
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

  test "invalid configuration renders errors without audit log" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference "AuditLog.count" do
      patch manager_standup_report_path(@owned_standup),
        params: {
          report_configuration: {
            delivery_channel: "bad channel",
            recipients_text: "bad recipient",
            report_format: "slack",
            detail_level: "detailed"
          }
        }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "must be a Slack channel name or ID without spaces"
    assert_includes response.body, "bad recipient"
  end

  test "manager queues manual report generation and writes audit log" do
    sign_in(@manager, "manager-access-token")

    assert_difference "ReportGeneration.count", 1 do
      assert_difference "AuditLog.where(action: 'report.manual_generation.queued').count", 1 do
        assert_enqueued_jobs 1 do
          post generate_manager_standup_report_path(@owned_standup)
        end
      end
    end

    assert_redirected_to manager_standup_report_path(@owned_standup, generated: "1")
    generation = ReportGeneration.recent.first
    assert_equal "queued", generation.status
    assert_equal @manager, generation.actor
    assert_equal "daily-reports", generation.delivery_channel
  end

  test "manual report generation failure is shown and audited" do
    report_configurations(:daily_report).update_column(:delivery_channel, "")
    sign_in(@manager, "manager-access-token")

    assert_difference "ReportGeneration.count", 1 do
      assert_difference "AuditLog.where(action: 'report.manual_generation.failure').count", 1 do
        assert_no_enqueued_jobs do
          post generate_manager_standup_report_path(@owned_standup)
        end
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Report configuration is invalid"
    assert ReportGeneration.recent.first.failed?
  end

  test "manager cannot configure or trigger reports for unowned standup" do
    sign_in(@manager, "manager-access-token")

    assert_no_difference [ "ReportConfiguration.count", "ReportGeneration.count", "AuditLog.count" ] do
      patch manager_standup_report_path(@unowned_standup),
        params: {
          report_configuration: {
            delivery_channel: "blocked",
            report_format: "slack",
            detail_level: "summary"
          }
        }
    end
    assert_response :forbidden

    assert_no_difference [ "ReportGeneration.count", "AuditLog.count" ] do
      post generate_manager_standup_report_path(@unowned_standup)
    end
    assert_response :forbidden
  end

  test "admin can configure reports for any standup" do
    sign_in(@admin, "admin-access-token")

    assert_difference "ReportConfiguration.count", 1 do
      patch manager_standup_report_path(@unowned_standup),
        params: {
          report_configuration: {
            delivery_channel: "weekly-reports",
            report_format: "slack",
            detail_level: "summary"
          }
        }
    end

    assert_redirected_to manager_standup_report_path(@unowned_standup, config_updated: "1")
    assert_equal "weekly-reports", @unowned_standup.reload.report_configuration.delivery_channel
  end

  private

  def sign_in(user, access_token)
    post session_path, params: { email: user.email, access_token: access_token }
    assert_redirected_to manager_standups_path
  end
end

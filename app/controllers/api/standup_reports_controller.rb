module Api
  # The standup's report settings, recent report generations, and "send a
  # report now".
  class StandupReportsController < BaseController
    CONFIG_UPDATED_NOTICE = "Report settings saved.".freeze
    GENERATED_NOTICE = "Report queued. It will appear in the history below when it's sent.".freeze

    before_action :require_manager!
    before_action :set_standup

    def show
      render json: report_payload
    end

    def update
      report_configuration = current_report_configuration
      report_configuration.assign_attributes(report_configuration_params)

      if report_configuration.save
        audit_change!(
          "report.configuration.update",
          auditable: @standup,
          metadata: {
            report_configuration_id: report_configuration.id,
            changes: audited_changes(report_configuration)
          }
        )
        render json: report_payload(report_configuration: report_configuration).merge(notice: CONFIG_UPDATED_NOTICE)
      else
        render_validation_errors(report_configuration.errors)
      end
    end

    def generate
      result = ReportGenerationService.new(standup: @standup, actor: principal.user).call
      audit_manual_generation!(result)

      if result.success?
        render json: report_payload.merge(notice: GENERATED_NOTICE)
      else
        render json: report_payload.merge(error: result.message, errors: [ result.message ]), status: :unprocessable_entity
      end
    end

    private

    def report_payload(report_configuration: nil)
      ReportPageSerializer.new(
        @standup,
        report_configuration: report_configuration || current_report_configuration,
        report_generations: @standup.report_generations.includes(:actor).recent.limit(10),
        summary: StandupAnalyticsService.new(@standup, period_days: period_days).summary
      ).as_json
    end

    def current_report_configuration
      @standup.report_configuration || @standup.build_report_configuration(
        delivery_channel: @standup.platform_channel,
        report_format: "slack",
        detail_level: "detailed",
        recipients: []
      )
    end

    def report_configuration_params
      params.require(:report_configuration).permit(:delivery_channel, :recipients_text, :report_format, :detail_level)
    end

    def audited_changes(report_configuration)
      report_configuration.saved_changes
        .except("created_at", "updated_at")
        .transform_values { |before, after| [ before, after ] }
    end

    def audit_manual_generation!(result)
      generation = result.report_generation
      metadata = {
        report_generation_id: generation&.id,
        status: generation&.status,
        delivery_channel: generation&.delivery_channel,
        recipients: generation&.recipients,
        report_format: generation&.report_format,
        detail_level: generation&.detail_level,
        error_message: generation&.error_message
      }.compact

      audit_change!(
        result.success? ? "report.manual_generation.queued" : "report.manual_generation.failure",
        auditable: @standup,
        metadata: metadata
      )
    end
  end
end

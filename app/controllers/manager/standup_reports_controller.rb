module Manager
  class StandupReportsController < ApplicationController
    before_action :set_standup

    def show
      load_report_state
    end

    def update
      @report_configuration = current_report_configuration
      @report_configuration.assign_attributes(report_configuration_params)

      if @report_configuration.save
        audit_manager_change!(
          "report.configuration.update",
          auditable: @standup,
          metadata: {
            report_configuration_id: @report_configuration.id,
            changes: audited_changes(@report_configuration)
          }
        )
        redirect_to manager_standup_report_path(@standup, config_updated: "1"), status: :see_other
      else
        load_report_state(report_configuration: @report_configuration)
        render :show, status: :unprocessable_entity
      end
    end

    def generate
      result = ReportGenerationService.new(standup: @standup, actor: current_user).call
      audit_manual_generation!(result)

      if result.success?
        redirect_to manager_standup_report_path(@standup, generated: "1"), status: :see_other
      else
        @manual_generation_error = result.message
        load_report_state
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def period_days
      params.fetch(:period_days, 30).to_i.clamp(1, 365)
    end

    def load_report_state(report_configuration: nil)
      @summary = StandupAnalyticsService.new(@standup, period_days: period_days).summary
      @report_configuration = report_configuration || current_report_configuration
      @report_generations = @standup.report_generations.includes(:actor).recent.limit(10)
    end

    def current_report_configuration
      @standup.report_configuration || @standup.build_report_configuration(
        delivery_channel: @standup.slack_channel,
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

      audit_manager_change!(
        result.success? ? "report.manual_generation.queued" : "report.manual_generation.failure",
        auditable: @standup,
        metadata: metadata
      )
    end
  end
end

# The console's Settings > Reports page: delivery settings, the options and per-platform
# hints for the form, the last few generations, and recent completion.
class ReportPageSerializer
  SLACK_CHANNEL_PLACEHOLDER = "daily-standup or C0123".freeze

  def initialize(standup, report_configuration:, report_generations:, summary:)
    @standup = standup
    @report_configuration = report_configuration
    @report_generations = report_generations
    @summary = summary
  end

  def as_json(*)
    {
      standup: StandupSerializer.new(@standup, include_counts: true).as_json,
      report_configuration: configuration_json,
      options: {
        report_formats: options_for(ReportConfiguration::REPORT_FORMATS),
        detail_levels: options_for(ReportConfiguration::DETAIL_LEVELS)
      },
      copy: {
        delivery_channel_placeholder: delivery_channel_placeholder,
        delivery_channel_hint: "Channel name or ID, without spaces.",
        recipients_placeholder: PlatformSerializer.copy_for(@standup.platform, :recipients_placeholder),
        recipients_hint: PlatformSerializer.copy_for(@standup.platform, :recipients_hint)
      },
      report_generations: @report_generations.map { |generation| generation_json(generation) },
      summary: {
        period_days: @summary[:period_days],
        completion_rate: @summary[:expected_responses].to_i.zero? ? nil : @summary[:completion_rate],
        completed_responses: @summary[:completed_responses],
        expected_responses: @summary[:expected_responses]
      }
    }
  end

  private

  def configuration_json
    configuration = @report_configuration
    {
      id: configuration.id,
      persisted: configuration.persisted?,
      delivery_channel: configuration.delivery_channel,
      recipients: Array(configuration.recipients),
      recipients_text: configuration.recipients_text,
      recipients_label: configuration.recipients_text.presence || "No one else",
      report_format: configuration.report_format,
      report_format_label: ReportConfiguration::REPORT_FORMATS[configuration.report_format],
      detail_level: configuration.detail_level,
      detail_level_label: ReportConfiguration::DETAIL_LEVELS[configuration.detail_level],
      updated_at: configuration.updated_at&.iso8601
    }
  end

  def generation_json(generation)
    status_label = generation.status.titleize
    {
      id: generation.id,
      status: generation.status,
      status_label: status_label,
      status_tone: UiFormat.status_tone(status_label),
      failed: generation.failed?,
      standup_date: generation.standup_date&.iso8601,
      requested_at: generation.requested_at&.iso8601,
      started_at: generation.started_at&.iso8601,
      completed_at: generation.completed_at&.iso8601,
      actor: generation.actor && { id: generation.actor.id, name: generation.actor.name },
      requested_by_label: generation.actor.present? ? "by #{generation.actor.name}" : "Scheduled",
      delivery_channel: generation.delivery_channel,
      recipients: Array(generation.recipients),
      report_format: generation.report_format,
      detail_level: generation.detail_level,
      detail_level_label: ReportConfiguration::DETAIL_LEVELS[generation.detail_level] || generation.detail_level,
      error_message: generation.error_message,
      response_count: generation.metadata["response_count"],
      delivery_count: generation.metadata["delivery_count"],
      result_label: result_label(generation)
    }
  end

  def result_label(generation)
    return generation.error_message if generation.failed?

    response_count = generation.metadata["response_count"]
    if response_count.present?
      delivery_count = generation.metadata["delivery_count"].to_i
      return "#{response_count} #{"response".pluralize(response_count.to_i)} to #{delivery_count} #{"destination".pluralize(delivery_count)}"
    end

    generation.completed_at.present? ? "Completed" : "Waiting for job"
  end

  def options_for(choices)
    choices.map { |value, label| { value: value, label: label } }
  end

  def delivery_channel_placeholder
    return SLACK_CHANNEL_PLACEHOLDER if @standup.platform.to_s == "slack"

    PlatformSerializer.copy_for(@standup.platform, :channel_id_placeholder)
  end
end

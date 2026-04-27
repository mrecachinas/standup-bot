class ReportGenerationService
  class Result
    attr_reader :report_generation, :message

    def initialize(success:, report_generation:, message:)
      @success = success
      @report_generation = report_generation
      @message = message
    end

    def success?
      @success
    end
  end

  def initialize(standup:, actor:, requested_at: Time.current)
    @standup = standup
    @actor = actor
    @requested_at = requested_at
  end

  def call
    configuration = effective_configuration
    unless configuration.valid?
      generation = create_failed_generation(configuration, configuration.errors.full_messages.to_sentence)
      return failure(generation, "Report configuration is invalid: #{generation.error_message}")
    end

    generation = build_generation(configuration)
    generation.save!
    StandupCollectionJob.perform_later(
      standup.id,
      generation.standup_date.iso8601,
      generation.timezone,
      generation.id,
      job_options(generation)
    )

    Result.new(success: true, report_generation: generation, message: "Report generation queued.")
  rescue StandardError => error
    generation ||= create_failed_generation(configuration, error.message)
    generation.mark_failed!(error.message) unless generation.failed?
    failure(generation, "Report generation could not be queued: #{error.message}")
  end

  private

  attr_reader :standup, :actor, :requested_at

  def effective_configuration
    standup.report_configuration || standup.build_report_configuration(
      delivery_channel: standup.slack_channel,
      report_format: "slack",
      detail_level: "detailed",
      recipients: []
    )
  end

  def build_generation(configuration)
    standup.report_generations.build(
      report_configuration: configuration.persisted? ? configuration : nil,
      actor: actor,
      status: "queued",
      delivery_channel: configuration.delivery_channel,
      recipients: configuration.recipients,
      report_format: configuration.report_format,
      detail_level: configuration.detail_level,
      standup_date: report_date,
      timezone: report_timezone.tzinfo.name,
      requested_at: requested_at,
      metadata: {}
    )
  end

  def create_failed_generation(configuration, message)
    generation = standup.report_generations.create!(
      report_configuration: configuration&.persisted? ? configuration : nil,
      actor: actor,
      status: "failed",
      delivery_channel: configuration&.delivery_channel.presence || "unconfigured",
      recipients: configuration&.recipients || [],
      report_format: valid_report_format(configuration),
      detail_level: valid_detail_level(configuration),
      standup_date: report_date,
      timezone: report_timezone.tzinfo.name,
      requested_at: requested_at,
      completed_at: Time.current,
      error_message: message.to_s.truncate(2_000),
      metadata: {}
    )
    generation
  end

  def job_options(generation)
    {
      "destination_channel" => generation.delivery_channel,
      "recipients" => generation.recipients,
      "report_format" => generation.report_format,
      "detail_level" => generation.detail_level
    }
  end

  def valid_report_format(configuration)
    value = configuration&.report_format
    ReportConfiguration::REPORT_FORMATS.key?(value) ? value : "slack"
  end

  def valid_detail_level(configuration)
    value = configuration&.detail_level
    ReportConfiguration::DETAIL_LEVELS.key?(value) ? value : "detailed"
  end

  def report_timezone
    Time.zone || Time.find_zone!("UTC")
  end

  def report_date
    report_timezone.today
  end

  def failure(generation, message)
    Result.new(success: false, report_generation: generation, message: message)
  end
end

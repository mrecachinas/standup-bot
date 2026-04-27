class StandupCollectionJob < ApplicationJob
  queue_as :default

  def perform(standup_id, standup_date = nil, timezone = nil, report_generation_id = nil, options = {})
    Rails.logger.info "Collecting standup responses for standup #{standup_id}"

    @report_generation = report_generation_id.present? ? ReportGeneration.find(report_generation_id) : nil
    @report_generation&.mark_running!

    standup = Standup.find(standup_id)
    options = (options || {}).with_indifferent_access
    report_zone = timezone.present? ? Standup.resolve_time_zone(timezone) : Time.zone
    report_date = standup_date.present? ? StandupResponse.normalize_date(standup_date) : report_zone.today
    destination_channel = options[:destination_channel].presence || standup.slack_channel
    recipients = Array(options[:recipients]).reject(&:blank?)
    report_format = options[:report_format].presence || "slack"
    detail_level = options[:detail_level].presence || "detailed"

    # Gather completed responses for the requested local standup date
    responses = StandupResponse
      .where(standup_id: standup.id, status: "completed")
      .for_standup_date(report_date, report_zone)

    if responses.empty?
      Rails.logger.info "No completed responses found for standup #{standup.name} today"
      no_responses_message = "No standup responses have been submitted today for #{standup.name}."
      slack_client.send_message(destination_channel, no_responses_message)
      deliver_recipient_copies(recipients, no_responses_message)
      @report_generation&.mark_succeeded!(
        metadata: generation_metadata(destination_channel, recipients, response_count: 0, detail_level: detail_level, report_format: report_format)
      )
      return
    end

    Rails.logger.info "Found #{responses.count} completed responses for standup #{standup.name}"

    summary_text = report_text(standup, responses, report_date, detail_level)
    deliver_report(destination_channel, summary_text, standup.outro, report_format)
    deliver_recipient_copies(recipients, summary_text)
    @report_generation&.mark_succeeded!(
      metadata: generation_metadata(destination_channel, recipients, response_count: responses.count, detail_level: detail_level, report_format: report_format)
    )

    Rails.logger.info "Successfully posted standup report for #{standup.name}"
  rescue StandardError => error
    @report_generation&.mark_failed!(
      error.message,
      metadata: {
        "error_class" => error.class.name
      }
    )
    raise
  end

  private

  def report_text(standup, responses, report_date, detail_level)
    if detail_level == "summary"
      summary_report_text(standup, responses, report_date)
    else
      detailed_report_text(responses)
    end
  end

  def detailed_report_text(responses)
    summary_parts = responses.map do |response|
      display_name = display_name_for(response.slack_id)

      answers = Array(response.answers).filter_map do |answer|
        next if answer["answer"].blank? || answer["answer"] == "(skipped)"

        "*#{answer["question"]}*\n#{answer["answer"]}"
      end

      next if answers.empty?

      "*#{display_name}*\n#{answers.join("\n")}"
    end.compact

    summary_parts.join("\n\n---\n\n")
  end

  def summary_report_text(standup, responses, report_date)
    lines = responses.map do |response|
      answered_count = Array(response.answers).count { |answer| answer["answer"].present? && answer["answer"] != "(skipped)" }
      "• #{display_name_for(response.slack_id)}: #{answered_count} answer(s)"
    end

    [
      "*#{standup.name} report for #{report_date.iso8601}*",
      "#{responses.count} completed response(s).",
      lines.join("\n")
    ].join("\n")
  end

  def display_name_for(slack_id)
    user_info = slack_client.get_user_info(slack_id)
    user_info&.dig("profile", "display_name").presence || user_info&.dig("name").presence || "Unknown User"
  end

  def deliver_report(destination_channel, summary_text, outro, report_format)
    if report_format == "plain_text"
      slack_client.send_message(destination_channel, [ summary_text, outro.presence ].compact.join("\n\n"))
    else
      slack_client.send_standup_summary(destination_channel, summary_text, outro)
    end
  end

  def deliver_recipient_copies(recipients, summary_text)
    recipients.each do |recipient|
      slack_client.send_message(recipient, summary_text)
    end
  end

  def generation_metadata(destination_channel, recipients, response_count:, detail_level:, report_format:)
    {
      "destination_channel" => destination_channel,
      "recipients" => recipients,
      "response_count" => response_count,
      "delivery_count" => 1 + recipients.count,
      "detail_level" => detail_level,
      "report_format" => report_format
    }
  end
end

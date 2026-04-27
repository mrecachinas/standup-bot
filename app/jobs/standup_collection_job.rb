class StandupCollectionJob < ApplicationJob
  queue_as :default

  def perform(standup_id, standup_date = nil, timezone = nil)
    Rails.logger.info "Collecting standup responses for standup #{standup_id}"

    standup = Standup.find(standup_id)
    report_zone = timezone.present? ? Standup.resolve_time_zone(timezone) : Time.zone
    report_date = standup_date.present? ? StandupResponse.normalize_date(standup_date) : report_zone.today

    # Gather completed responses for the requested local standup date
    responses = StandupResponse
      .where(standup_id: standup.id, status: "completed")
      .for_standup_date(report_date, report_zone)

    if responses.empty?
      Rails.logger.info "No completed responses found for standup #{standup.name} today"
      slack_client.send_message(
        standup.slack_channel,
        "No standup responses have been submitted today for #{standup.name}."
      )
      return
    end

    Rails.logger.info "Found #{responses.count} completed responses for standup #{standup.name}"

    # Build summary text
    summary_parts = responses.map do |response|
      user_info = slack_client.get_user_info(response.slack_id)
      display_name = user_info&.dig("profile", "display_name") || user_info&.dig("name") || "Unknown User"

      answers = response.answers.filter_map do |answer|
        next if answer["answer"].blank? || answer["answer"] == "(skipped)"
        "*#{answer["question"]}*\n#{answer["answer"]}"
      end

      next if answers.empty?

      "*#{display_name}*\n#{answers.join("\n")}"
    end.compact

    summary_text = summary_parts.join("\n\n---\n\n")

    slack_client.send_standup_summary(standup.slack_channel, summary_text, standup.outro)

    Rails.logger.info "Successfully posted standup report for #{standup.name}"
  end
end

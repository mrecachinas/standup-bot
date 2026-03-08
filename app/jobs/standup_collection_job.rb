class StandupCollectionJob < ApplicationJob
  queue_as :default

  def perform(standup_id)
    Rails.logger.info "Collecting standup responses for standup #{standup_id}"

    standup = Standup.find(standup_id)

    # Gather today's completed responses
    responses = StandupResponse
      .where(standup_id: standup.id, status: "completed")
      .where("created_at >= ?", Date.today.beginning_of_day)

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

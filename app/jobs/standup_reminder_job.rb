class StandupReminderJob < ApplicationJob
  queue_as :default

  def perform(standup_id = nil)
    responses = StandupResponse.pending.includes(:standup)
    responses = responses.where(standup_id: standup_id) if standup_id.present?

    responses.find_each do |response|
      next unless reminder_due?(response)

      send_reminder(response)
    end
  end

  private

  def reminder_due?(response)
    standup = response.standup
    return false unless standup.active?
    return false unless standup.reminder_enabled?
    return false if standup.skips_occurrence_on?(response.standup_date)
    return false if response.reminder_count.to_i >= standup.max_reminders

    reminder_reference = response.last_reminder_at || response.created_at
    reminder_reference <= standup.reminder_after_minutes.minutes.ago
  end

  def send_reminder(response)
    standup = response.standup
    answered = response.answers&.size || 0
    total = standup.questions.size
    chat = chat_for(standup)
    fmt = chat.formatter
    question = standup.questions[answered]

    reminder = "⏰ #{fmt.bold(standup.name)} is still waiting on you (#{answered} of #{total} answered). " \
      "Reply here to pick up where you left off, or #{fmt.code("skip")} to pass on this one."
    chat.send_direct_message(
      response.platform_user_id,
      [ reminder, (StandupFormatter.format_question(question, formatter: fmt) if question.present?) ].compact.join("\n\n")
    )

    response.update!(
      reminder_count: response.reminder_count.to_i + 1,
      last_reminder_at: Time.current
    )
  end
end

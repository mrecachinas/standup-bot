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
    return false unless standup.reminder_enabled?
    return false if response.reminder_count.to_i >= standup.max_reminders

    reminder_reference = response.last_reminder_at || response.created_at
    reminder_reference <= standup.reminder_after_minutes.minutes.ago
  end

  def send_reminder(response)
    standup = response.standup
    answered = response.answers&.size || 0
    total = standup.questions.size

    slack_client.send_message(
      response.slack_id,
      "Friendly reminder: your #{standup.name} standup is still in progress " \
        "(#{answered}/#{total} questions answered). Reply in this DM to continue, " \
        "or type `skip` to skip the current question."
    )

    response.update!(
      reminder_count: response.reminder_count.to_i + 1,
      last_reminder_at: Time.current
    )
  end
end

# Sends a run's next question (index: how many answers it had when the
# question was due). It runs right after an answer is saved (perform_now), on
# retries, and from StandupUpdateSweepJob, and sends nothing if the run has
# moved on or the question already went out. Queued runs share the person's
# inbound concurrency group, so they don't race their next message.
class StandupPromptJob < ApplicationJob
  queue_as :inbound
  limits_concurrency key: ->(standup_response, _index) {
      ApplicationJob.inbound_concurrency_key(standup_response.standup.platform, standup_response.platform_user_id)
    },
    group: INBOUND_CONCURRENCY_GROUP, duration: INBOUND_CONCURRENCY_DURATION

  def perform(standup_response, index)
    standup_response.reload if standup_response.persisted?
    return unless standup_response.status == "pending" && standup_response.answers.size == index
    return if standup_response.prompted_since_last_answer?

    StandupResponseService.send_next_question(standup_response)
  end
end

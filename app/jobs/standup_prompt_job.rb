# Sends a run's next question (index: how many answers it had when the
# question was due). It runs right after an answer is saved (perform_now) and
# again on retries, and sends nothing if the run has moved on meanwhile.
class StandupPromptJob < ApplicationJob
  queue_as :inbound

  def perform(standup_response, index)
    standup_response.reload if standup_response.persisted?
    return unless standup_response.status == "pending" && standup_response.answers.size == index

    StandupResponseService.send_next_question(standup_response)
  end
end

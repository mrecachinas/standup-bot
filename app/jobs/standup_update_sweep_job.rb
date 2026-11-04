# Finishes what a worker stopping at the wrong moment can leave undone: a
# finished run whose update was never posted or whose sign-off never went
# out, or a pending run whose next question was never sent after an answer
# was saved. Normally StandupUpdateJob and StandupPromptJob run right then and
# retry on their own, so this only looks at runs left that way for a while.
class StandupUpdateSweepJob < ApplicationJob
  queue_as :default
  limits_concurrency key: "run", on_conflict: :discard, duration: 15.minutes

  GRACE = 15.minutes
  PROMPT_GRACE = 5.minutes
  LOOKBACK = 1.day

  def perform
    StandupResponse.where(status: "completed", signed_off_at: nil)
      .where.not(prompted_at: nil)
      .where(updated_at: LOOKBACK.ago..GRACE.ago)
      .find_each { |standup_response| StandupUpdateJob.perform_later(standup_response, announce: true) }

    StandupResponse.pending.includes(:standup)
      .where.not(prompted_at: nil)
      .where(updated_at: LOOKBACK.ago..PROMPT_GRACE.ago)
      .find_each do |standup_response|
        next unless standup_response.next_question_unsent?

        StandupPromptJob.perform_later(standup_response, standup_response.answers.size)
      end
  end
end

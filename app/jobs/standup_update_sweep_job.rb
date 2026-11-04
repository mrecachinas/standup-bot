# Finishes runs whose update was never posted or whose sign-off never went
# out, say because a worker stopped right after the last answer was saved.
# Normally StandupUpdateJob runs right then and retries on its own, so this
# only looks at runs left that way for longer than those retries take.
class StandupUpdateSweepJob < ApplicationJob
  queue_as :default
  limits_concurrency key: "run", on_conflict: :discard, duration: 15.minutes

  GRACE = 15.minutes
  LOOKBACK = 1.day

  def perform
    StandupResponse.where(status: "completed", signed_off_at: nil)
      .where.not(prompted_at: nil)
      .where(updated_at: LOOKBACK.ago..GRACE.ago)
      .find_each { |standup_response| StandupUpdateJob.perform_later(standup_response, announce: true) }
  end
end

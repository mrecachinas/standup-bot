# Runs SlackDmBackfill over every pending Slack run from the last day. Queued
# when the Socket Mode client reconnects after a gap no connection covered, or
# by hand (bin/rails slack:backfill_dms) after an outage in HTTP mode.
class SlackDmBackfillJob < ApplicationJob
  queue_as :default
  limits_concurrency key: "run", on_conflict: :discard, duration: 30.minutes

  # Runs older than this are past saving; they expire anyway.
  LOOKBACK = 1.day

  def perform
    backfill = SlackDmBackfill.new
    handled = 0
    pending_runs.find_each do |standup_response|
      handled += backfill.call(standup_response)
    rescue Slack::Web::Api::Errors::TooManyRequestsError
      raise
    rescue StandardError => error
      Rails.logger.error "Couldn't backfill DMs for standup response #{standup_response.id}: #{error.class} - #{error.message}"
    end
    Rails.logger.info "Backfilled #{handled} missed Slack DM(s)"
    StandupMetrics.track("slack.dm_backfill", handled: handled)
  end

  private

  def pending_runs
    StandupResponse.pending
      .joins(:standup).where(standups: { platform: "slack" })
      .where.not(dm_channel: [ nil, "" ])
      .where(created_at: LOOKBACK.ago..)
  end
end

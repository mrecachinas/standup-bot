class DataCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform
    StandupMetrics.track("data_cleanup.started")

    old_responses_deleted = cleanup_old_responses
    pending_expired = cleanup_stale_pending_responses
    processed_messages_deleted = cleanup_processed_messages
    vacuumed = vacuum_database_if_sqlite

    result = {
      old_responses_deleted: old_responses_deleted,
      pending_expired: pending_expired,
      processed_messages_deleted: processed_messages_deleted,
      vacuumed: vacuumed
    }

    # Event payloads are filtered by filter_parameters, which would mask a key
    # containing "message".
    StandupMetrics.track("data_cleanup.completed", result.except(:processed_messages_deleted).merge(processed_chat_records_deleted: processed_messages_deleted))
    result
  end

  private

  def cleanup_old_responses
    cutoff = retention_days.days.ago
    deleted = 0

    StandupResponse.where("created_at < ?", cutoff).in_batches(of: cleanup_batch_size) do |batch|
      deleted += batch.delete_all
    end

    deleted
  end

  def cleanup_stale_pending_responses
    cutoff = stale_pending_days.days.ago

    StandupResponse.pending
      .where("created_at < ?", cutoff)
      .update_all(status: "expired", updated_at: Time.current)
  end

  def cleanup_processed_messages
    deleted = 0
    ProcessedChatMessage.where(created_at: ...ProcessedChatMessage::RETENTION.ago).in_batches(of: cleanup_batch_size) do |batch|
      deleted += batch.delete_all
    end
    deleted
  end

  def vacuum_database_if_sqlite
    return false unless ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")

    ActiveRecord::Base.connection.execute("VACUUM")
    true
  end

  def retention_days
    configured_integer("RESPONSE_RETENTION_DAYS", :response_retention_days, 90)
  end

  def cleanup_batch_size
    configured_integer("CLEANUP_BATCH_SIZE", :cleanup_batch_size, 1000)
  end

  def stale_pending_days
    configured_integer("STALE_PENDING_DAYS", :stale_pending_days, 7)
  end

  def configured_integer(env_key, config_key, default)
    Integer(ENV.fetch(env_key, retention_config.fetch(config_key, default)))
  rescue ArgumentError, TypeError
    default
  end

  def retention_config
    Rails.application.config.retention || {}
  end
end

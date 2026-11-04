# A message someone sent the bot that has been handled. See .process_once.
class ProcessedChatMessage < ApplicationRecord
  # Long enough to cover every redelivery and DM-history backfill.
  RETENTION = 7.days

  # Runs the block once per message and returns whether it ran. The record and
  # whatever the block saves commit together, so if the block fails (or the
  # process dies) the message stays unhandled and the retry runs it. A
  # duplicate arriving meanwhile waits on the record's lock, then is skipped.
  # Messages without an ID (nothing to tell duplicates apart) always run.
  def self.process_once(platform:, platform_user_id:, message_id:)
    if message_id.blank?
      yield
      return true
    end

    transaction do
      claimed = claim(platform, platform_user_id, message_id)
      yield if claimed
      claimed
    end
  end

  def self.handled?(platform:, platform_user_id:, message_id:)
    message_id.present? && exists?(platform: platform.to_s, platform_user_id: platform_user_id.to_s, message_id: message_id.to_s)
  end

  def self.claim(platform, platform_user_id, message_id)
    # A savepoint, so a duplicate's failed insert doesn't abort the outer
    # transaction on PostgreSQL.
    transaction(requires_new: true) do
      create!(platform: platform.to_s, platform_user_id: platform_user_id.to_s, message_id: message_id.to_s)
    end
    true
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "Skipping #{platform} message #{message_id} from #{platform_user_id}; it was already handled"
    false
  end
  private_class_method :claim
end

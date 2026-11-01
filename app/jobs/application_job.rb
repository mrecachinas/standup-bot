class ApplicationJob < ActiveJob::Base
  around_perform :track_and_notify_failures

  # Retry only transient/network errors, not permanent failures
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: :exponentially_longer, attempts: 5
  retry_on ChatPlatform::RateLimitedError, wait: :exponentially_longer, attempts: 5
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
           wait: :exponentially_longer, attempts: 3

  discard_on ActiveRecord::RecordNotFound

  private

  def chat_for(standup)
    ChatPlatform.for_standup(standup)
  end

  def track_and_notify_failures
    yield
  rescue StandardError => exception
    StandupMetrics.track(
      "job.failed",
      job_class: self.class.name,
      job_id: job_id,
      error_class: exception.class.name,
      error_message: exception.message
    )
    notify_admin_channel(exception)
    raise
  end

  def notify_admin_channel(exception)
    channel = ENV["ADMIN_CHANNEL"].presence
    return unless channel

    ChatPlatform.for(:slack).send_message(channel, "⚠️ Job #{self.class.name} failed: #{exception.class} - #{exception.message}")
  rescue StandardError => notification_error
    Rails.logger.error "Failed to notify admin channel: #{notification_error.class} - #{notification_error.message}"
  end
end

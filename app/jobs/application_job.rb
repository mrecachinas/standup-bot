class ApplicationJob < ActiveJob::Base
  # Jobs handling what people send the bot share this concurrency group, keyed
  # by platform and person, so one person's messages and clicks are handled one
  # at a time in the order they arrived (Solid Queue releases blocked jobs in
  # order). Quick replies can't race, and "foo" is recorded before "bar".
  INBOUND_CONCURRENCY_GROUP = "chat-inbound".freeze
  INBOUND_CONCURRENCY_DURATION = 5.minutes

  def self.inbound_concurrency_key(platform, platform_user_id)
    "#{platform}:#{platform_user_id}" if platform_user_id.present?
  end

  around_perform :track_and_notify_failures

  # Retry only transient/network errors, not permanent failures
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
  retry_on ChatPlatform::RateLimitedError, wait: :polynomially_longer, attempts: 5
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
           Faraday::ConnectionFailed, Faraday::TimeoutError,
           # Slack timeouts, 5xx, and unparseable responses, plus its own internal_error.
           Slack::Web::Api::Errors::ServerError, Slack::Web::Api::Errors::InternalError,
           # Teams: Microsoft unreachable or a 5xx.
           Microsoft::TransientApiError,
           wait: :polynomially_longer, attempts: 3

  discard_on ActiveRecord::RecordNotFound

  # Every log line and error report from the job carries its job_class, job_id,
  # and queue. A job run inside another (perform_now) puts the outer job's
  # context back when it finishes. A failure that retry_on or discard_on
  # doesn't handle is reported here, while the job's context is still set;
  # Rails' own report of the same error after the job is then a no-op.
  def perform_now
    Instrumentation.with_context(job_class: self.class.name, job_id: job_id, queue: queue_name) do
      super
    rescue StandardError => exception
      Rails.error.report(exception, handled: false, source: "application.active_job")
      raise
    end
  end

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
      error_class: exception.class.name
    )
    notify_admin_channel(exception)
    raise
  end

  ADMIN_CHANNEL_ENV = { slack: "ADMIN_CHANNEL", teams: "TEAMS_ADMIN_CHANNEL" }.freeze
  # One notice per kind of failure in this window, so a burst of the same
  # failure (say, many people's DMs failing at once) doesn't flood the channel.
  ADMIN_NOTICE_INTERVAL = 15.minutes

  def notify_admin_channel(exception, context: nil)
    return if admin_notice_muted?(exception, context)

    subject = context || "Job #{self.class.name} failed"
    text = "⚠️ #{subject}: #{exception.class} - #{exception.message} " \
      "(similar failures are muted for #{ADMIN_NOTICE_INTERVAL.inspect})"
    ADMIN_CHANNEL_ENV.each do |platform, env_name|
      channel = ENV[env_name].presence
      next unless channel

      begin
        ChatPlatform.for(platform).send_message(channel, text)
      rescue StandardError => notification_error
        Rails.error.report(notification_error, context: { platform: platform }, source: "application_job.notify_admin_channel")
      end
    end
  end

  # The first failure of a kind in the window claims it atomically (an
  # increment in the shared cache), so concurrent failures across workers send
  # one notice. Best effort: if the cache fails, the notice goes out and the
  # original error is what's raised.
  def admin_notice_muted?(exception, context)
    key = [ "admin-notice", self.class.name, exception.class.name, context ].compact.join("/")
    count = Rails.cache.increment(key, 1, expires_in: ADMIN_NOTICE_INTERVAL)
    count.present? && count > 1
  rescue StandardError => cache_error
    Rails.error.report(cache_error, source: "application_job.admin_notice_throttle")
    false
  end
end

class StandupMetrics
  class << self
    def track(event, tags = {})
      payload = {
        event: event,
        tags: tags.compact,
        timestamp: Time.current.iso8601
      }

      Rails.logger.info(payload.to_json)
      cache_last_seen(event)
    end

    def last_seen(event)
      Rails.cache.read(cache_key(event))
    rescue StandardError
      nil
    end

    private

    def cache_last_seen(event)
      Rails.cache.write(cache_key(event), Time.current.iso8601, expires_in: 7.days)
    rescue StandardError
      nil
    end

    def cache_key(event)
      "standup_metrics:#{event}:last_seen"
    end
  end
end

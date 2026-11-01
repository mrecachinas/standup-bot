# Entry point for chat platform adapters. Shared standup code asks this
# module for an adapter and never talks to a platform SDK directly.
module ChatPlatform
  DEFAULT = :slack
  ADAPTERS = {
    slack: "ChatPlatform::SlackAdapter",
    teams: "ChatPlatform::TeamsAdapter"
  }.freeze

  UnknownPlatform = Class.new(ArgumentError)

  class RateLimitedError < StandardError
    attr_reader :retry_after

    def initialize(message = "Chat platform rate limit reached", retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  class << self
    def for(platform)
      key = normalize_key(platform)
      adapters[key] ||= ADAPTERS.fetch(key).constantize.new
    end

    def for_standup(standup)
      self.for(standup.respond_to?(:platform) ? standup.platform : DEFAULT)
    end

    def keys
      ADAPTERS.keys
    end

    def supported?(platform)
      ADAPTERS.key?(platform.to_s.presence&.to_sym)
    end

    def enabled
      keys.map { |key| self.for(key) }.select(&:configured?)
    end

    def reset!
      @adapters = {}
    end

    private

    def adapters
      @adapters ||= {}
    end

    def normalize_key(platform)
      key = platform.to_s.presence&.to_sym || DEFAULT
      raise UnknownPlatform, "Unknown chat platform: #{platform.inspect}" unless ADAPTERS.key?(key)

      key
    end
  end
end

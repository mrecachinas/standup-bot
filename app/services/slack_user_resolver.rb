class SlackUserResolver
  ResolutionError = Class.new(StandardError)

  ResolvedUser = Struct.new(:platform_user_id, :display_name, :cached_timezone, :avatar_url, keyword_init: true)

  def initialize(service: SlackIntegrationService.new)
    @service = service
  end

  def resolve(identifier, fallback_name: nil)
    lookup, mention_name = parse_slack_mention(identifier)
    lookup = identifier.to_s.strip if lookup.blank?

    result = service.resolve_user(lookup)
    raise ResolutionError, resolution_error_message(result) unless result.success?

    record = result.records.first
    ResolvedUser.new(
      platform_user_id: record.fetch("id"),
      display_name: fallback_name.presence || mention_name.presence || record["label"].presence || record["display_name"].presence || record["real_name"].presence || record["name"].presence || record.fetch("id"),
      cached_timezone: record["tz"].presence,
      avatar_url: record["avatar_url"].presence
    )
  end

  private

  attr_reader :service

  def parse_slack_mention(identifier)
    match = identifier.to_s.strip.match(/\A<@(?<id>[^>|]+)(?:\|(?<name>[^>]+))?>\z/)
    return [ nil, nil ] unless match

    [ match[:id], match[:name] ]
  end

  def resolution_error_message(result)
    [ result.message, result.action ].compact.join(" ")
  end
end

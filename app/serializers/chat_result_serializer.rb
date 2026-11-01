# A ChatIntegrationService::Result (connection check, discovery, or test
# message), with discovery records cleaned up for display.
class ChatResultSerializer
  def initialize(result, kind: nil)
    @result = result
    @kind = kind
  end

  def as_json(*)
    return if @result.nil?

    {
      status: @result.status,
      success: @result.success?,
      message: @result.message,
      action: @result.action,
      error_code: @result.error_code,
      metadata: metadata,
      records: @result.records && Array(@result.records).map { |record| record_json(record) }
    }
  end

  private

  def metadata
    return if @result.metadata.blank?

    @result.metadata.to_h.map { |key, value| { key: key.to_s, label: key.to_s.humanize, value: value } }
  end

  def record_json(record)
    record = record.to_h.stringify_keys
    user = @kind == :users || record.key?("tz")
    {
      id: record["id"],
      kind: user ? "user" : "channel",
      label: record["label"] || record["name"] || record["id"],
      name: record["name"],
      tz: record["tz"],
      email: record["email"],
      is_private: record["is_private"] || false,
      is_member: record["is_member"] || false,
      avatar_url: (record["avatar_url"] if SlackAvatar.safe_url?(record["avatar_url"])),
      detail: detail(record, user)
    }
  end

  # The line under each result: "C123 · @jane · Europe/London · private".
  def detail(record, user)
    [
      record["id"],
      ("@#{record["name"]}" if user && record["name"].present? && record.key?("tz")),
      record["tz"].presence,
      ("private" if record["is_private"]),
      ("bot is a member" if record["is_member"])
    ].compact.join(" · ")
  end
end

require "set"

class StandupParticipantImporter
  Result = Struct.new(:created, :updated, :unchanged, :deactivated, :errors, :changes, keyword_init: true) do
    def success?
      errors.empty?
    end

    def changed_count
      created.size + updated.size + deactivated.size
    end

    def summary
      {
        created_count: created.size,
        updated_count: updated.size,
        unchanged_count: unchanged.size,
        deactivated_count: deactivated.size,
        error_count: errors.size
      }
    end
  end

  Change = Struct.new(:participant, :action, :metadata, keyword_init: true)

  def initialize(standup, now: Time.current, user_resolver: nil)
    @standup = standup
    @now = now
    @user_resolver = user_resolver
  end

  def import_text(text)
    result = new_result
    rows = parse_text_rows(text, result)

    if rows.empty? && result.errors.empty?
      result.errors << "Enter at least one participant to import."
      return result
    end

    import_rows(rows, result)
    result
  end

  def sync_profiles(profiles, deactivate_missing: false)
    result = new_result
    rows = Array(profiles).filter_map.with_index(1) do |profile, index|
      profile_row(profile, index, result)
    end

    if rows.empty? && result.errors.empty?
      result.errors << "No Slack members were returned for that channel."
      return result
    end

    import_rows(rows, result)
    deactivate_missing_participants(rows, result) if deactivate_missing && result.errors.empty?
    result
  end

  private

  attr_reader :standup, :now, :user_resolver

  def new_result
    Result.new(created: [], updated: [], unchanged: [], deactivated: [], errors: [], changes: [])
  end

  def parse_text_rows(text, result)
    text.to_s.lines.filter_map.with_index(1) do |line, line_number|
      parse_text_row(line, line_number, result)
    end
  end

  def parse_text_row(line, line_number, result)
    stripped = line.strip
    return if stripped.blank? || stripped.start_with?("#")

    values = parse_values(stripped)
    mention_id, mention_name = parse_slack_mention(values[0])
    fallback_name = values[1].presence || mention_name
    resolved_user = resolve_user_identifier(mention_id || values[0], fallback_name: fallback_name, result: result, label: "Line #{line_number}")

    return unless resolved_user

    {
      slack_id: resolved_user.slack_id,
      slack_name: fallback_name.presence || resolved_user.slack_name,
      cached_timezone: values[2].presence || resolved_user.cached_timezone,
      active: parse_active(values[3]),
      source: "bulk_import",
      line: line_number
    }
  end

  def parse_values(line)
    if line.include?(",")
      line.split(",", -1).map { |value| value.to_s.strip }
    else
      line.split(/\s+/, 4).map(&:strip)
    end
  end

  def parse_slack_mention(value)
    match = value.to_s.strip.match(/\A<@(?<id>[^>|]+)(?:\|(?<name>[^>]+))?>\z/)
    return [ nil, nil ] unless match

    [ match[:id], match[:name] ]
  end

  def normalize_slack_id(value)
    value.to_s.strip.delete_prefix("@").upcase
  end

  def resolve_user_identifier(identifier, fallback_name:, result:, label:)
    if user_resolver
      user_resolver.resolve(identifier, fallback_name: fallback_name)
    else
      slack_id = normalize_slack_id(identifier)
      if slack_id.blank?
        result.errors << "#{label}: Slack user is required."
        return
      end

      SlackUserResolver::ResolvedUser.new(slack_id: slack_id, slack_name: fallback_name.presence || slack_id)
    end
  rescue SlackUserResolver::ResolutionError => error
    result.errors << "#{label}: #{error.message}"
    nil
  end

  def parse_active(value)
    return true if value.nil? || value.to_s.strip.blank?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def profile_row(profile, index, result)
    slack_id = normalize_slack_id(profile_value(profile, :slack_id) || profile_value(profile, "slack_id") || profile_value(profile, :id) || profile_value(profile, "id"))

    if slack_id.blank?
      result.errors << "Slack profile #{index}: Slack user ID is required."
      return
    end

    {
      slack_id: slack_id,
      slack_name: profile_value(profile, :slack_name).presence ||
        profile_value(profile, "slack_name").presence ||
        profile_value(profile, :name).presence ||
        profile_value(profile, "name").presence ||
        slack_id,
      cached_timezone: profile_value(profile, :cached_timezone).presence ||
        profile_value(profile, "cached_timezone").presence ||
        profile_value(profile, :tz).presence ||
        profile_value(profile, "tz").presence,
      active: true,
      source: "slack_sync",
      line: index
    }
  end

  def profile_value(profile, key)
    profile[key]
  rescue NoMethodError
    profile.public_send(key) if profile.respond_to?(key)
  end

  def import_rows(rows, result)
    rows.each do |row|
      participant = standup.standup_participants.find_or_initialize_by(slack_id: row[:slack_id])
      was_new = participant.new_record?
      attributes = participant_attributes(row, participant)
      participant.assign_attributes(attributes)

      if participant.new_record? || participant.changed?
        save_participant(participant, row, result, was_new)
      else
        result.unchanged << participant
      end
    end
  end

  def participant_attributes(row, participant)
    attributes = {
      slack_name: row[:slack_name],
      active: row[:active],
      cached_timezone: row[:cached_timezone]
    }.reject { |_key, value| value.nil? }

    if row[:cached_timezone].present? && participant.cached_timezone != row[:cached_timezone]
      attributes[:cached_timezone_updated_at] = now if participant.has_attribute?(:cached_timezone_updated_at)
    end

    attributes
  end

  def save_participant(participant, row, result, was_new)
    before = was_new ? {} : audited_participant_attributes(participant)

    if participant.save
      after = audited_participant_attributes(participant)
      if was_new
        result.created << participant
        result.changes << Change.new(
          participant: participant,
          action: "standup_participant.create",
          metadata: row_metadata(row).merge(standup_id: standup.id, attributes: after)
        )
      else
        result.updated << participant
        result.changes << Change.new(
          participant: participant,
          action: "standup_participant.update",
          metadata: row_metadata(row).merge(standup_id: standup.id, before: before, changes: audited_saved_changes(participant))
        )
      end
    else
      result.errors << row_error(row, participant.errors.full_messages.to_sentence)
    end
  end

  def deactivate_missing_participants(rows, result)
    incoming_slack_ids = rows.map { |row| row[:slack_id] }.to_set

    standup.standup_participants.where(active: true).where.not(slack_id: incoming_slack_ids).find_each do |participant|
      before = audited_participant_attributes(participant)
      participant.update!(active: false)
      result.deactivated << participant
      result.changes << Change.new(
        participant: participant,
        action: "standup_participant.update",
        metadata: {
          standup_id: standup.id,
          source: "slack_sync",
          sync_action: "deactivate_missing",
          before: before,
          changes: audited_saved_changes(participant)
        }
      )
    end
  end

  def row_metadata(row)
    { source: row[:source], line: row[:line] }.compact
  end

  def row_error(row, message)
    label = row[:line] ? "Line #{row[:line]}" : row[:slack_id]
    "#{label}: #{message}"
  end

  def audited_saved_changes(participant)
    participant.saved_changes.except("updated_at").transform_values { |before, after| [ before, after ] }
  end

  def audited_participant_attributes(participant)
    participant.attributes.slice(
      "id",
      "standup_id",
      "slack_id",
      "slack_name",
      "active",
      "cached_timezone",
      "cached_timezone_updated_at",
      "vacation_until"
    )
  end
end

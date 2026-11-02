# The people rows the console's standup editor sends: existing participants
# (possibly edited or marked for removal), new rows, and handles typed into
# "Add people". Problems are added to the standup's errors so they show up
# with the rest of the form.
class StandupRosterRows
  ROW_FIELDS = [ :id, :platform_user_id, :original_platform_user_id, :display_name, :cached_timezone, :active, :_destroy ].freeze

  # Rows for the editor to show for an existing standup.
  def self.for(standup)
    standup.standup_participants.order(:display_name, :platform_user_id).map do |participant|
      {
        id: participant.id,
        platform_user_id: participant.platform_user_id,
        display_name: participant.display_name,
        cached_timezone: participant.cached_timezone,
        avatar_url: participant.avatar_url,
        active: participant.active?,
        destroy: false
      }
    end
  end

  # rows: hashes with ROW_FIELDS. handles: text with handles separated by commas or new lines.
  def initialize(standup, rows: [], handles: nil)
    @standup = standup
    @rows = Array(rows).map { |row| sanitize(row) } + handle_rows(handles)
  end

  # Looks up anyone given by name or handle, then checks every row.
  def validate
    # Rows are checked against the standup's platform; an unknown platform is
    # already a standup error.
    return if rows.empty? || !ChatPlatform.supported?(standup.platform)

    resolve
    check_rows
    check_conflicts_with_existing_participants
  end

  # Saves the rows and returns what changed, for the audit log.
  def apply!
    rows.reject { |row| blank?(row) }.flat_map do |row|
      if row[:id].present?
        apply_existing_row!(row)
      elsif row[:destroy]
        []
      else
        [ change("added", standup.standup_participants.create!(participant_attributes(row))) ]
      end
    end
  end

  private

  attr_reader :standup, :rows

  def handle_rows(text)
    text.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq.map do |handle|
      { id: nil, platform_user_id: normalize_identifier(handle), display_name: "", cached_timezone: nil, active: true, destroy: false }
    end
  end

  def sanitize(row)
    attributes = row.to_h.stringify_keys
    platform_user_id = normalize_identifier(attributes["platform_user_id"].to_s.strip)
    # If someone typed a different person into a pre-filled row, the cached
    # name and timezone belong to the old person, so look the new one up instead.
    original_platform_user_id = attributes["original_platform_user_id"].to_s.strip
    replaced = original_platform_user_id.present? && platform_user_id != normalize_identifier(original_platform_user_id)
    {
      id: attributes["id"].presence,
      platform_user_id: platform_user_id,
      display_name: replaced ? "" : attributes["display_name"].to_s.strip,
      cached_timezone: replaced ? nil : attributes["cached_timezone"].to_s.strip.presence,
      active: boolean(attributes.key?("active") ? attributes["active"] : true),
      destroy: boolean(attributes["_destroy"])
    }
  end

  def normalize_identifier(identifier)
    normalized = identifier.delete_prefix("@")
    chat.looks_like_user_id?(normalized) ? chat.normalize_user_id(normalized) : identifier
  end

  def chat
    @chat ||= ChatPlatform.for(ChatPlatform.supported?(standup.platform) ? standup.platform : ChatPlatform::DEFAULT)
  end

  def resolve
    resolver = ChatUserResolver.for(standup.platform)

    rows.each_with_index do |row, index|
      next if blank?(row) || row[:destroy] || row[:platform_user_id].blank?
      next if chat.valid_user_id?(row[:platform_user_id]) && row[:display_name].present?

      row.merge!(resolver.resolve(row[:platform_user_id], fallback_name: row[:display_name]).fill_in(row))
    rescue ChatUserResolver::ResolutionError => error
      add_error("Participant #{index + 1}: #{error.message}")
    end
  end

  def check_rows
    seen = {}

    rows.each_with_index do |row, index|
      next if blank?(row)

      label = "Participant #{index + 1}"
      if row[:id].present? && !standup.standup_participants.exists?(id: row[:id])
        add_error("#{label} could not be found for this standup")
        next
      end
      next if row[:destroy]

      add_error("#{label} #{chat.label} ID can't be blank") if row[:platform_user_id].blank?
      add_error("#{label} name can't be blank") if row[:display_name].blank?
      if row[:platform_user_id].present? && !chat.valid_user_id?(row[:platform_user_id])
        add_error("#{label} #{chat.label} ID must be #{chat.user_id_hint}")
      end
      if row[:cached_timezone].present? && !StandupParticipant.valid_timezone?(row[:cached_timezone])
        add_error("#{label} timezone is not valid")
      end

      next if row[:platform_user_id].blank?

      if seen.key?(row[:platform_user_id])
        add_error("#{label} duplicates #{seen[row[:platform_user_id]]}")
      else
        seen[row[:platform_user_id]] = label
      end
    end
  end

  def check_conflicts_with_existing_participants
    return unless standup.persisted?

    existing_ids = standup.standup_participants.where.not(id: rows.filter_map { |row| row[:id] }).pluck(:platform_user_id)
    rows.each_with_index do |row, index|
      next if row[:destroy] || row[:platform_user_id].blank? || !existing_ids.include?(row[:platform_user_id])

      add_error("Participant #{index + 1} #{chat.label} ID is already in this standup")
    end
  end

  def apply_existing_row!(row)
    participant = standup.standup_participants.find(row[:id])

    if row[:destroy]
      snapshot = snapshot(participant)
      participant.destroy!
      return [ snapshot.merge(action: "removed") ]
    end

    before = snapshot(participant)
    participant.update!(participant_attributes(row))
    return [] unless participant.previous_changes.except("updated_at").any?

    [ change("updated", participant, before: before) ]
  end

  def participant_attributes(row)
    attributes = row.slice(:platform_user_id, :display_name, :cached_timezone, :active)
    attributes[:avatar_url] = row[:avatar_url] if SlackAvatar.safe_url?(row[:avatar_url])
    attributes
  end

  def snapshot(participant)
    participant.attributes.slice("id", "platform_user_id", "display_name", "cached_timezone", "active")
  end

  def change(action, participant, before: nil)
    payload = snapshot(participant).merge(action: action)
    payload[:before] = before if before
    payload
  end

  def blank?(row)
    row.values_at(:id, :platform_user_id, :display_name, :cached_timezone).all?(&:blank?)
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def add_error(message)
    standup.errors.add(:base, message)
  end
end

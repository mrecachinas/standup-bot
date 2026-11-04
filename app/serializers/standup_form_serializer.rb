# Everything the standup editor needs to render: the standup itself, the
# templates and platforms to pick from, the question and people rows, the
# timezone and weekday choices, Teams channel options, and the schedule preview.
class StandupFormSerializer
  BLANK_TEMPLATE_ATTRIBUTES = { schedule_type: "weekdays", schedule_days: [], default_hour: 9, default_minute: 30, questions: [] }.freeze
  TEMPLATES = {
    "daily" => {
      label: "Daily standup",
      description: "Weekdays at 9:30 AM",
      attributes: {
        schedule_type: "weekdays", schedule_days: [], default_hour: 9, default_minute: 30,
        questions: [ "What did you get done yesterday?", "What are you working on today?", "Is anything blocking you?" ]
      }
    },
    "weekly" => {
      label: "Weekly check-in",
      description: "Mondays at 10:00 AM",
      attributes: {
        schedule_type: "weekly", schedule_days: [ 1 ], default_hour: 10, default_minute: 0,
        questions: [ "What were your wins last week?", "What are your priorities this week?", "Where could you use help?" ]
      }
    },
    "retro" => {
      label: "Friday retro",
      description: "Fridays at 3:00 PM",
      attributes: {
        schedule_type: "weekly", schedule_days: [ 5 ], default_hour: 15, default_minute: 0,
        questions: [ "What went well this week?", "What didn't go well?", "What should we try next week?" ]
      }
    }
  }.freeze
  TEMPLATE_KEYS = (TEMPLATES.keys + [ "blank" ]).freeze
  DEFAULT_TEMPLATE = "daily".freeze
  WEEKDAY_OPTIONS = [
    [ "Sunday", 0 ],
    [ "Monday", 1 ],
    [ "Tuesday", 2 ],
    [ "Wednesday", 3 ],
    [ "Thursday", 4 ],
    [ "Friday", 5 ],
    [ "Saturday", 6 ]
  ].freeze
  DAY_PRESETS = [
    { label: "Weekdays", days: [ 1, 2, 3, 4, 5 ] },
    { label: "Every day", days: [ 0, 1, 2, 3, 4, 5, 6 ] },
    { label: "Mon, Wed, Fri", days: [ 1, 3, 5 ] }
  ].freeze
  FREQUENCY_OPTIONS = [
    { value: "weekly", label: "Every week" },
    { value: "biweekly", label: "Every other week", hint: "Every other week runs on a single day." },
    { value: "monthly", label: "Once a month" }
  ].freeze
  RESPECT_TIMEZONE_OPTIONS = [
    { value: true, label: "Each person's local time" },
    { value: false, label: "The same moment for everyone (UTC)" }
  ].freeze
  QUESTION_SUGGESTIONS = [
    "What did you get done yesterday?",
    "What are you working on today?",
    "Is anything blocking you?",
    "What are you proud of this week?",
    "Where could you use help?",
    "How are you feeling today, from 1 to 5?"
  ].freeze
  TEAMS_CHANNEL_FALLBACK_MESSAGE = "Set up Teams on the Integrations page to pick a channel from a list.".freeze

  def self.template_attributes(key)
    (TEMPLATES.dig(key, :attributes) || BLANK_TEMPLATE_ATTRIBUTES).deep_dup
  end

  def self.time_zone_options
    @time_zone_options ||= ActiveSupport::TimeZone.all.map { |zone| { name: zone.name, iana: zone.tzinfo.identifier } }.freeze
  end

  # participant_rows: hashes with id, platform_user_id, display_name,
  # cached_timezone, avatar_url, active and destroy.
  # channel_options: a ChatIntegrationService::Result for Teams standups, or nil.
  def initialize(standup, participant_rows:, platform_options:, preview:, template_key: nil, channel_options: nil,
    default_preview_timezone: nil, detect_preview_timezone: false)
    @standup = standup
    @participant_rows = participant_rows
    @platform_options = platform_options
    @preview = preview
    @template_key = template_key
    @channel_options = channel_options
    @default_preview_timezone = default_preview_timezone
    @detect_preview_timezone = detect_preview_timezone
  end

  def as_json(*)
    {
      mode: @standup.persisted? ? "edit" : "new",
      standup: StandupSerializer.new(@standup, include_counts: @standup.persisted?).as_json,
      templates: templates,
      template_key: @template_key,
      platform: PlatformSerializer.new(@standup.platform).as_json,
      platform_options: @platform_options.map { |key| PlatformSerializer.new(key).as_json },
      show_platform_picker: @standup.new_record? && @platform_options.size > 1,
      platform_locked: @standup.persisted?,
      channel: channel,
      channel_options: channel_options,
      question_rows: question_rows,
      question_suggestions: QUESTION_SUGGESTIONS.map { |text| { text: text, used: question_rows.include?(text) } },
      participant_rows: @participant_rows.map { |row| participant_row(row) },
      participants_hint: participants_hint,
      weekday_options: WEEKDAY_OPTIONS.rotate(1).map { |label, value| { value: value, label: label, short_label: label.first(3) } },
      day_presets: DAY_PRESETS,
      frequency_options: FREQUENCY_OPTIONS,
      respect_timezone_options: RESPECT_TIMEZONE_OPTIONS,
      monthly_day: schedule_picker[:monthly_day] || 1,
      send_time: format("%02d:%02d", @standup.default_hour || 9, @standup.default_minute || 0),
      advanced_open: advanced_open?,
      default_preview_timezone: @default_preview_timezone,
      detect_preview_timezone: @detect_preview_timezone,
      preview_timezone: @preview.zone.name,
      time_zone_options: self.class.time_zone_options,
      schedule_preview: @preview.as_json,
      message_preview: message_preview
    }
  end

  private

  def templates
    TEMPLATES.map do |key, template|
      question_count = template[:attributes][:questions].size
      {
        key: key,
        label: template[:label],
        description: template[:description],
        question_count: question_count,
        meta: "#{template[:description]} · #{question_count} #{"question".pluralize(question_count)}"
      }
    end
  end

  def schedule_picker
    @schedule_picker ||= UiFormat.schedule_picker_state(@standup)
  end

  def advanced_open?
    schedule_picker[:frequency] != "weekly" || !@standup.respect_timezone? || @standup.errors.any?
  end

  # Always end with one empty row so there's somewhere to type a new question.
  def question_rows
    @question_rows ||= Array(@standup.questions).map(&:to_s).reject(&:blank?) + [ "" ]
  end

  # Slack searches channels as you type (stored by ID, with a typed #name as
  # a fallback); Teams picks from discovered channels, or falls back to a
  # typed ID when discovery isn't available.
  def channel
    if @standup.chat_platform.key == :teams
      choices = teams_channel_choices
      {
        input: choices.any? ? "select" : "text",
        value: @standup.platform_channel,
        name: @standup.platform_channel_name,
        choices: choices,
        placeholder: choices.any? ? "Pick a Teams channel" : PlatformSerializer.copy_for(:teams, :channel_id_placeholder),
        hint: (@channel_options&.message || TEAMS_CHANNEL_FALLBACK_MESSAGE if teams_channel_records.empty?)
      }
    else
      {
        input: "search",
        prefix: "#",
        value: @standup.platform_channel.to_s.delete_prefix("#"),
        name: @standup.platform_channel_name,
        choices: [],
        placeholder: "Search channels or type a name",
        hint: nil
      }
    end
  end

  def channel_options
    return unless @channel_options

    {
      records: Array(@channel_options.records),
      success: @channel_options.success?,
      message: @channel_options.message
    }
  end

  def teams_channel_records
    @channel_options&.success? ? Array(@channel_options.records) : []
  end

  # Keep the current channel selectable even when discovery doesn't list it.
  def teams_channel_choices
    records = teams_channel_records
    return [] if records.empty?

    choices = records.map { |record| { id: record["id"], label: record["label"] } }
    if @standup.platform_channel.present? && choices.none? { |choice| choice[:id] == @standup.platform_channel }
      choices.unshift({ id: @standup.platform_channel, label: @standup.platform_channel_name.presence || @standup.platform_channel })
    end
    choices
  end

  def participant_row(row)
    name = row[:display_name].presence || row[:platform_user_id]
    pending = row[:id].blank? && row[:display_name].blank?
    {
      id: row[:id],
      platform_user_id: row[:platform_user_id],
      original_platform_user_id: row[:platform_user_id],
      display_name: row[:display_name],
      cached_timezone: row[:cached_timezone],
      avatar_url: row[:avatar_url],
      active: row[:active] ? true : false,
      destroy: row[:destroy] ? true : false,
      label: name,
      pending: pending,
      meta: if pending then "looked up on save" elsif !row[:active] then "inactive" end
    }
  end

  def participants_hint
    "Names and timezones come from #{@standup.chat_platform.label}."
  end

  def message_preview
    present_questions = question_rows.select(&:present?)
    {
      time: UiFormat.format_clock(@standup.default_hour || 9, @standup.default_minute || 0),
      intro: @standup.intro,
      question_count: [ present_questions.size, 1 ].max,
      first_question: present_questions.first || "Your first question shows up here.",
      hint: "Asked one at a time in a #{@standup.chat_platform.label} DM. Press Enter to add another."
    }
  end
end

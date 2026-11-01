module Api
  # Standups for scripts (the admin token) and the console (a session). Both
  # send `standup: {...}`. The console's editor adds its own fields (a day
  # picker, send time, question rows and people rows); those are only read
  # when they're present, so script requests behave exactly as before.
  class StandupsController < BaseController
    DEFAULT_PREVIEW_TIMEZONE = StandupSchedulePreviewSerializer::DEFAULT_TIMEZONE
    WEEKDAY_NUMBERS = [ 1, 2, 3, 4, 5 ].freeze
    PARTICIPANT_ROW_FIELDS = [ :id, :platform_user_id, :original_platform_user_id, :display_name, :cached_timezone, :active, :_destroy ].freeze
    # Fields only the console's editor sends. Any of them switches on the
    # editor's parsing of the schedule and questions.
    CONSOLE_SCHEDULE_FIELDS = %w[frequency days monthly_day send_time question_rows questions_text schedule_days_text].freeze
    CONSOLE_PARTICIPANT_FIELDS = %w[participants participant_handles].freeze

    before_action :require_manager!
    before_action :set_standup, only: [ :show, :edit, :update, :destroy, :pause, :resume ]
    before_action :skip_authorization, only: [ :index, :new, :create, :preview, :channel_options ]

    def index
      standups = manageable_standups.order(:name)
      render json: {
        standups: standups.map { |standup| serialize_standup(standup, include_counts: true) }
      }
    end

    # ?include=overview adds what the console's overview page shows.
    def show
      payload = { standup: serialize_standup(@standup, include_counts: true) }
      if included?("overview")
        payload[:overview] = StandupOverviewSerializer.new(@standup, preview_timezone: preview_timezone_param).as_json
      end
      render json: payload
    end

    def new
      template_key = params[:template].presence_in(StandupFormSerializer::TEMPLATE_KEYS) || StandupFormSerializer::DEFAULT_TEMPLATE
      platform = params[:platform].presence_in(enabled_platform_keys) || enabled_platform_keys.first
      @standup = Standup.new(
        platform: platform,
        respect_timezone: true,
        active: true,
        **StandupFormSerializer.template_attributes(template_key)
      )
      creator_rows = creator_participant_rows
      @default_preview_timezone = rails_time_zone_name(creator_rows.first&.dig(:cached_timezone))

      render json: form_payload(
        participant_rows: creator_rows,
        template_key: template_key,
        detect_preview_timezone: @default_preview_timezone.nil?
      )
    end

    def edit
      render json: form_payload(participant_rows: participant_rows_for(@standup))
    end

    def create
      @standup = Standup.new(standup_params)
      participant_rows = participant_rows_from_params
      return render_validation_errors(@standup.errors) unless valid_standup_form?(participant_rows)

      Standup.transaction do
        @standup.save!
        # Console users own what they create; the token and admins see everything already.
        @standup.standup_ownerships.create!(user: principal.user, role: "owner") if principal.user && !principal.admin?
        participant_changes = apply_participant_rows!(@standup, participant_rows)
        metadata = { attributes: audited_standup_attributes(@standup) }
        metadata[:participants] = participant_changes if participant_form?
        audit_change!("standup.create", auditable: @standup, metadata: metadata)
      end

      StandupMetrics.track("admin.standup_created", standup_id: @standup.id)
      render json: { standup: serialize_standup(@standup, include_counts: true), notice: "#{@standup.name} was created." }, status: :created
    rescue ActiveRecord::RecordInvalid => error
      render_record_invalid(error)
    end

    # The platform can't change after creation; the model rejects it.
    def update
      @standup.assign_attributes(standup_params)
      participant_rows = participant_rows_from_params
      return render_validation_errors(@standup.errors) unless valid_standup_form?(participant_rows)

      Standup.transaction do
        @standup.save!
        metadata = { changes: audited_changes(@standup) }
        participant_changes = apply_participant_rows!(@standup, participant_rows)
        metadata[:participants] = participant_changes if participant_form?
        audit_change!("standup.update", auditable: @standup, metadata: metadata)
      end

      StandupMetrics.track("admin.standup_updated", standup_id: @standup.id)
      render json: { standup: serialize_standup(@standup, include_counts: true), notice: "#{@standup.name} was updated." }
    rescue ActiveRecord::RecordInvalid => error
      render_record_invalid(error)
    end

    # The editor's live "Next runs" preview. Nothing is saved.
    def preview
      @standup = Standup.new(standup_params)
      render json: schedule_preview.as_json
    end

    # Channels for the editor's Teams channel picker. Only admins see private channels.
    def channel_options
      platform = params[:platform].presence || "teams"
      unless ChatPlatform.supported?(platform)
        render json: { error: "Unknown chat platform: #{platform}" }, status: :unprocessable_entity
        return
      end

      result = discover_channels(platform)
      render json: { platform: platform.to_s, records: Array(result.records), success: result.success?, message: result.message }
    end

    def destroy
      standup = @standup
      snapshot = audited_standup_attributes(standup)
      standup.destroy!
      StandupMetrics.track("admin.standup_deleted", standup_id: standup.id)
      audit_change!("standup.destroy", auditable: standup, metadata: { attributes: snapshot })
      head :no_content
    end

    def pause
      change_active_state!(false, "standup.pause")
    end

    def resume
      change_active_state!(true, "standup.resume")
    end

    private

    def included?(section)
      params[:include].to_s.split(",").map(&:strip).include?(section)
    end

    def serialize_standup(standup, include_counts: false)
      StandupSerializer.new(standup, include_counts: include_counts).as_json
    end

    def standup_params
      attrs = params.require(:standup).permit(
        :name,
        :platform,
        :platform_channel,
        :platform_channel_name,
        :intro,
        :outro,
        :schedule_type,
        :default_hour,
        :default_minute,
        :respect_timezone,
        :active,
        :reminder_enabled,
        :reminder_after_minutes,
        :max_reminders,
        :send_time,
        :monthly_day,
        :questions_text,
        :schedule_days_text,
        :frequency,
        :participant_handles,
        question_rows: [],
        questions: [],
        schedule_days: [],
        days: [],
        participants: PARTICIPANT_ROW_FIELDS
      ).to_h.except("participants", "participant_handles")
      return attrs unless attrs.keys.intersect?(CONSOLE_SCHEDULE_FIELDS)

      console_standup_attributes(attrs)
    end

    # How the console editor's fields map onto the standup's columns.
    def console_standup_attributes(attrs)
      apply_day_picker!(attrs) if attrs.key?("frequency")

      if attrs.key?("question_rows") || attrs.key?("questions_text") || attrs.key?("questions")
        attrs["questions"] = questions_from_attrs(attrs)
      end
      if attrs.key?("schedule_type") || attrs.key?("schedule_days") || attrs.key?("schedule_days_text") || attrs.key?("monthly_day")
        attrs["schedule_days"] = schedule_days_from_attrs(attrs)
      end
      apply_send_time!(attrs)

      attrs.except("question_rows", "questions_text", "schedule_days_text", "monthly_day", "days")
    end

    # The editor picks days and a repeat interval; turn that into the
    # schedule type the scheduler understands. "weekly" and "biweekly" only
    # support a single day, so several days become "custom".
    def apply_day_picker!(attrs)
      frequency = attrs.delete("frequency").to_s
      days = Array(attrs.delete("days")).filter_map { |day| Integer(day, exception: false) }.select { |day| (0..6).cover?(day) }.uniq.sort

      case frequency
      when "monthly"
        attrs["schedule_type"] = "monthly"
      when "biweekly"
        attrs["schedule_type"] = "biweekly"
        attrs["schedule_days"] = days
        @schedule_error = "Every other week runs on one day. Pick a single day." unless days.size == 1
      else
        attrs["schedule_type"], attrs["schedule_days"] =
          if days.size == 7 then [ "daily", [] ]
          elsif days == WEEKDAY_NUMBERS then [ "weekdays", [] ]
          elsif days.size == 1 then [ "weekly", days ]
          else [ "custom", days ]
          end
        @schedule_error = "Pick at least one day." if days.empty?
      end
    end

    def questions_from_attrs(attrs)
      if attrs.key?("question_rows")
        split_lines(Array(attrs["question_rows"]).join("\n"))
      elsif attrs.key?("questions_text")
        split_lines(attrs["questions_text"])
      else
        split_lines(Array(attrs["questions"]).join("\n"))
      end
    end

    def schedule_days_from_attrs(attrs)
      if attrs["schedule_type"] == "monthly"
        Array(attrs["monthly_day"].presence || attrs["schedule_days"]).flatten.reject(&:blank?).first(1)
      elsif attrs.key?("schedule_days_text")
        split_numbers(attrs["schedule_days_text"])
      else
        Array(attrs["schedule_days"]).reject(&:blank?)
      end
    end

    def apply_send_time!(attrs)
      return unless attrs.key?("send_time")

      send_time = attrs.delete("send_time").to_s
      if send_time.match?(/\A\d{1,2}:\d{2}\z/)
        hour, minute = send_time.split(":").map(&:to_i)
        attrs["default_hour"] = hour
        attrs["default_minute"] = minute
      else
        attrs["default_hour"] = nil
        attrs["default_minute"] = nil
      end
    end

    def split_lines(value)
      value.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def split_numbers(value)
      value.to_s.split(/[,\s]+/).reject(&:blank?)
    end

    def valid_standup_form?(participant_rows)
      standup_valid = @standup.valid?
      if @schedule_error
        @standup.errors.add(:base, @schedule_error)
        standup_valid = false
      end
      # People rows are checked against the standup's platform, so an unknown
      # platform (already an error above) leaves them alone.
      if participant_rows.any? && ChatPlatform.supported?(@standup.platform)
        resolve_participant_rows(participant_rows)
        validate_participant_rows(participant_rows)
      end
      standup_valid && @standup.errors.none?
    end

    def render_record_invalid(error)
      @standup.errors.add(:base, error.record.errors.full_messages.to_sentence) unless error.record.equal?(@standup)
      render_validation_errors(@standup.errors)
    end

    def change_active_state!(active, action)
      previous_active = @standup.active?
      notice = nil

      if previous_active != active
        @standup.update!(active: active)
        notice = active ? "#{@standup.name} was resumed." : "#{@standup.name} was paused."
        audit_change!(action, auditable: @standup, metadata: { changes: { active: [ previous_active, active ] } })
      end

      render json: { standup: serialize_standup(@standup, include_counts: true), notice: notice }
    end

    # --- The editor's form payload ---------------------------------------

    def form_payload(participant_rows:, template_key: nil, detect_preview_timezone: false)
      StandupFormSerializer.new(
        @standup,
        participant_rows: participant_rows,
        platform_options: (enabled_platform_keys | [ @standup.platform.to_s ]).select { |key| ChatPlatform.supported?(key) },
        preview: schedule_preview,
        template_key: template_key,
        channel_options: (discover_channels(:teams) if @standup.platform == "teams"),
        default_preview_timezone: @default_preview_timezone,
        detect_preview_timezone: detect_preview_timezone
      ).as_json
    end

    def schedule_preview
      StandupSchedulePreviewSerializer.new(@standup, timezone: preview_timezone_param, error: @schedule_error)
    end

    def preview_timezone_param
      params[:preview_timezone].presence || @default_preview_timezone || DEFAULT_PREVIEW_TIMEZONE
    end

    def enabled_platform_keys
      @enabled_platform_keys ||= ChatPlatform.enabled.map { |adapter| adapter.key.to_s }.presence || [ ChatPlatform::DEFAULT.to_s ]
    end

    def discover_channels(platform)
      ChatIntegrationService.for(platform).discover_channels(limit: ChatIntegrationService::MAX_LIMIT, include_private: principal.admin?)
    end

    # Whoever creates a standup usually takes part in it, so start with them
    # on the roster.
    def creator_participant_rows
      return [] unless current_user

      platform = @standup.platform.presence || ChatPlatform::DEFAULT.to_s
      member_user_id = current_member.platform_user_id if current_member&.platform.to_s == platform
      platform_user_id = current_user.platform_user_id_for(platform).presence || member_user_id.presence
      return [] unless platform_user_id

      known = StandupParticipant.where(platform_user_id: platform_user_id).order(Arel.sql("cached_timezone IS NULL"), updated_at: :desc).first
      [ {
        id: nil,
        platform_user_id: platform_user_id,
        display_name: known&.display_name.presence || current_user.name,
        cached_timezone: known&.cached_timezone,
        avatar_url: known&.avatar_url || current_user.avatar_url,
        active: true,
        destroy: false
      } ]
    end

    def rails_time_zone_name(iana_name)
      return if iana_name.blank?

      ActiveSupport::TimeZone.all.find { |zone| zone.tzinfo.identifier == iana_name }&.name
    end

    def participant_rows_for(standup)
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

    # --- People rows from the editor ---------------------------------------

    # Script requests never send people rows, so their roster is left alone.
    def participant_form?
      return @participant_form if defined?(@participant_form)

      standup = params[:standup]
      @participant_form = standup.respond_to?(:key?) && CONSOLE_PARTICIPANT_FIELDS.any? { |key| standup.key?(key) }
    end

    def participant_rows_from_params
      return [] unless participant_form?

      permitted = params.require(:standup).permit(:participant_handles, participants: PARTICIPANT_ROW_FIELDS)

      ordered_participant_rows(permitted[:participants]).map { |row| sanitize_participant_row(row) } +
        participant_handle_rows(permitted[:participant_handles])
    end

    # "Add people" accepts several handles separated by commas or new lines.
    def participant_handle_rows(text)
      text.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq.map do |handle|
        { id: nil, platform_user_id: normalize_participant_identifier(handle), display_name: "", cached_timezone: nil, active: true, destroy: false }
      end
    end

    # Rows arrive as an array, or as a hash keyed by position from form posts.
    def ordered_participant_rows(raw_rows)
      case raw_rows
      when ActionController::Parameters
        raw_rows.to_h.sort_by { |index, _row| index.to_i }.map(&:last)
      when Hash
        raw_rows.sort_by { |index, _row| index.to_i }.map(&:last)
      when Array
        raw_rows
      else
        []
      end
    end

    def sanitize_participant_row(row)
      attributes = row.to_h.stringify_keys
      platform_user_id = normalize_participant_identifier(attributes["platform_user_id"].to_s.strip)
      # If someone typed a different person into a pre-filled row, the cached
      # name and timezone belong to the old person, so look the new one up instead.
      original_platform_user_id = attributes["original_platform_user_id"].to_s.strip
      replaced = original_platform_user_id.present? && platform_user_id != normalize_participant_identifier(original_platform_user_id)
      {
        id: attributes["id"].presence,
        platform_user_id: platform_user_id,
        display_name: replaced ? "" : attributes["display_name"].to_s.strip,
        cached_timezone: replaced ? nil : attributes["cached_timezone"].to_s.strip.presence,
        active: boolean_param(attributes.key?("active") ? attributes["active"] : true),
        destroy: boolean_param(attributes["_destroy"])
      }
    end

    def validate_participant_rows(rows)
      seen_ids = {}
      submitted_ids = rows.filter_map { |row| row[:id] }
      chat = @standup.chat_platform

      rows.each_with_index do |row, index|
        next if blank_participant_row?(row)

        row_label = "Participant #{index + 1}"
        if row[:id].present? && !@standup.standup_participants.exists?(id: row[:id])
          @standup.errors.add(:base, "#{row_label} could not be found for this standup")
          next
        end
        next if row[:destroy]

        @standup.errors.add(:base, "#{row_label} #{chat.label} ID can't be blank") if row[:platform_user_id].blank?
        @standup.errors.add(:base, "#{row_label} name can't be blank") if row[:display_name].blank?

        if row[:platform_user_id].present? && !chat.valid_user_id?(row[:platform_user_id])
          @standup.errors.add(:base, "#{row_label} #{chat.label} ID must be #{chat.user_id_hint}")
        end

        if row[:cached_timezone].present? && !StandupParticipant.valid_timezone?(row[:cached_timezone])
          @standup.errors.add(:base, "#{row_label} timezone is not valid")
        end

        next if row[:platform_user_id].blank?

        if seen_ids.key?(row[:platform_user_id])
          @standup.errors.add(:base, "#{row_label} duplicates #{seen_ids[row[:platform_user_id]]}")
        else
          seen_ids[row[:platform_user_id]] = row_label
        end
      end

      validate_existing_participant_conflicts(rows, submitted_ids)
    end

    def validate_existing_participant_conflicts(rows, submitted_ids)
      return unless @standup.persisted?

      existing_ids = @standup.standup_participants.where.not(id: submitted_ids).pluck(:platform_user_id)
      rows.each_with_index do |row, index|
        next if row[:destroy] || row[:platform_user_id].blank? || !existing_ids.include?(row[:platform_user_id])

        @standup.errors.add(:base, "Participant #{index + 1} #{@standup.chat_platform.label} ID is already in this standup")
      end
    end

    def normalize_participant_identifier(identifier)
      normalized = identifier.delete_prefix("@")
      participant_platform.looks_like_user_id?(normalized) ? participant_platform.normalize_user_id(normalized) : identifier
    end

    # Rows are parsed before the standup is built on create, so fall back to the submitted platform.
    def participant_platform
      platform = @standup&.platform.presence || params.dig(:standup, :platform).presence
      ChatPlatform.supported?(platform) ? ChatPlatform.for(platform) : ChatPlatform.for(ChatPlatform::DEFAULT)
    end

    def resolve_participant_rows(rows)
      rows.each_with_index do |row, index|
        next if blank_participant_row?(row) || row[:destroy] || row[:platform_user_id].blank?
        next if @standup.chat_platform.valid_user_id?(row[:platform_user_id]) && row[:display_name].present?

        resolved_user = user_resolver.resolve(row[:platform_user_id], fallback_name: row[:display_name])
        row[:platform_user_id] = resolved_user.platform_user_id
        row[:display_name] = row[:display_name].presence || resolved_user.display_name
        row[:cached_timezone] = row[:cached_timezone].presence || resolved_user.cached_timezone
        row[:avatar_url] = resolved_user.avatar_url
      rescue ChatUserResolver::ResolutionError => error
        @standup.errors.add(:base, "Participant #{index + 1}: #{error.message}")
      end
    end

    def user_resolver
      @user_resolver ||= ChatUserResolver.new(service: ChatIntegrationService.for(@standup.platform))
    end

    def apply_participant_rows!(standup, rows)
      changes = []

      rows.each do |row|
        next if blank_participant_row?(row)

        if row[:id].present?
          changes.concat(apply_existing_participant_row!(standup, row))
        elsif !row[:destroy]
          participant = standup.standup_participants.create!(participant_attributes(row))
          changes << participant_change("added", participant)
        end
      end

      changes
    end

    def apply_existing_participant_row!(standup, row)
      participant = standup.standup_participants.find(row[:id])

      if row[:destroy]
        snapshot = participant_snapshot(participant)
        participant.destroy!
        return [ snapshot.merge(action: "removed") ]
      end

      before = participant_snapshot(participant)
      participant.update!(participant_attributes(row))
      return [] unless participant.previous_changes.except("updated_at").any?

      [ participant_change("updated", participant, before: before) ]
    end

    def participant_attributes(row)
      attributes = {
        platform_user_id: row[:platform_user_id],
        display_name: row[:display_name],
        cached_timezone: row[:cached_timezone],
        active: row[:active]
      }
      attributes[:avatar_url] = row[:avatar_url] if SlackAvatar.safe_url?(row[:avatar_url])
      attributes
    end

    def participant_snapshot(participant)
      participant.attributes.slice("id", "platform_user_id", "display_name", "cached_timezone", "active")
    end

    def participant_change(action, participant, before: nil)
      payload = participant_snapshot(participant).merge(action: action)
      payload[:before] = before if before
      payload
    end

    def blank_participant_row?(row)
      row[:id].blank? &&
        row[:platform_user_id].blank? &&
        row[:display_name].blank? &&
        row[:cached_timezone].blank?
    end

    def boolean_param(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    # --- Audit ---------------------------------------------------------------

    def audited_changes(standup)
      standup.saved_changes.except("updated_at").transform_values { |before, after| [ before, after ] }
    end

    def audited_standup_attributes(standup)
      standup.attributes.slice(
        "id",
        "name",
        "platform",
        "platform_channel",
        "schedule_type",
        "schedule_days",
        "default_hour",
        "default_minute",
        "respect_timezone",
        "active"
      )
    end
  end
end

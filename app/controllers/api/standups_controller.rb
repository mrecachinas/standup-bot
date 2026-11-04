module Api
  # Standups for scripts (the admin token) and the console (a session). Both
  # send `standup: {...}`. The console's editor adds its own fields (a day
  # picker, send time, question rows and people rows); those are only read
  # when they're present (see StandupEditorAttributes and StandupRosterRows),
  # so script requests behave exactly as before.
  class StandupsController < BaseController
    DEFAULT_PREVIEW_TIMEZONE = StandupSchedulePreviewSerializer::DEFAULT_TIMEZONE
    ROSTER_FIELDS = %w[participants participant_handles].freeze

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
        @default_preview_timezone = participant_preview_timezone(@standup)
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
      render json: form_payload(participant_rows: StandupRosterRows.for(@standup))
    end

    def create
      @standup = Standup.new(standup_params)
      roster = roster_from_params
      return render_validation_errors(@standup.errors) unless valid_standup_form?(roster)

      Standup.transaction do
        @standup.save!
        # Console users own what they create; the token and admins see everything already.
        @standup.standup_ownerships.create!(user: principal.user, role: "owner") if principal.user && !principal.admin?
        metadata = { attributes: audited_standup_attributes(@standup) }
        metadata[:participants] = roster.apply! if roster
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
      roster = roster_from_params
      return render_validation_errors(@standup.errors) unless valid_standup_form?(roster)

      Standup.transaction do
        @standup.save!
        metadata = { changes: audited_changes(@standup) }
        metadata[:participants] = roster.apply! if roster
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

    # Channels for the editor's channel pickers: Teams' list and Slack's
    # search (`query`). Only admins see private channels.
    def channel_options
      platform = params[:platform].presence || "teams"
      unless ChatPlatform.supported?(platform)
        render json: { error: "Unknown chat platform: #{platform}" }, status: :unprocessable_entity
        return
      end

      result = discover_channels(platform, query: params[:query].to_s.strip.delete_prefix("#").presence)
      records = Array(result.records).map { |record| record.to_h.slice("id", "name", "label", "is_private", "is_member") }
      render json: { platform: platform.to_s, records: records, success: result.success?, message: result.message, action: result.action }
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
        participants: StandupRosterRows::ROW_FIELDS
      ).to_h.except(*ROSTER_FIELDS)

      editor = StandupEditorAttributes.new(attrs)
      @schedule_error = editor.schedule_error
      editor.attributes
    end

    # Script requests never send people rows, so their roster is left alone.
    def roster_from_params
      return unless params[:standup].respond_to?(:key?) && ROSTER_FIELDS.any? { |key| params[:standup].key?(key) }

      permitted = params.require(:standup).permit(:participant_handles, participants: StandupRosterRows::ROW_FIELDS)
      StandupRosterRows.new(@standup, rows: permitted[:participants], handles: permitted[:participant_handles])
    end

    def valid_standup_form?(roster)
      @standup.valid?
      @standup.errors.add(:base, @schedule_error) if @schedule_error
      roster&.validate
      @standup.errors.none?
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

    def discover_channels(platform, query: nil)
      ChatIntegrationService.for(platform).discover_channels(query: query, limit: ChatIntegrationService::MAX_LIMIT, include_private: principal.admin?)
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

    # A standup sent in each person's local time previews in the timezone most
    # of its people are in, rather than UTC.
    def participant_preview_timezone(standup)
      return unless standup.respect_timezone

      timezone = standup.standup_participants
        .where(active: true)
        .where.not(cached_timezone: [ nil, "" ])
        .group(:cached_timezone)
        .order(Arel.sql("COUNT(*) DESC"), :cached_timezone)
        .limit(1)
        .pluck(:cached_timezone)
        .first
      # Cached timezones are usually IANA names, shown by their Rails name;
      # one that's already a Rails name (or has no Rails name) is kept as is.
      rails_time_zone_name(timezone) || (timezone if StandupParticipant.valid_timezone?(timezone))
    end

    def rails_time_zone_name(iana_name)
      return if iana_name.blank?

      ActiveSupport::TimeZone.all.find { |zone| zone.tzinfo.identifier == iana_name }&.name
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

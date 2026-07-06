module Manager
  class StandupsController < ApplicationController
    before_action :set_standup, only: [ :show, :edit, :update, :destroy, :pause, :resume ]

    PREVIEW_OCCURRENCE_COUNT = 5
    BLANK_QUESTION_ROWS = 3
    BLANK_PARTICIPANT_ROWS = 3
    DEFAULT_PREVIEW_TIMEZONE = "UTC"
    WEEKDAY_OPTIONS = [
      [ "Sunday", 0 ],
      [ "Monday", 1 ],
      [ "Tuesday", 2 ],
      [ "Wednesday", 3 ],
      [ "Thursday", 4 ],
      [ "Friday", 5 ],
      [ "Saturday", 6 ]
    ].freeze

    def index
      @visibility = dashboard_visibility
      @period_days = dashboard_period_days
      @standups = filtered_standups.order(:name)
      @dashboard_items = StandupDashboard.new(@standups, period_days: @period_days).items
    end

    def show
      @preview_timezone = DEFAULT_PREVIEW_TIMEZONE
      prepare_schedule_preview
    end

    def new
      @standup = Standup.new(schedule_type: "daily", questions: [], respect_timezone: true, active: true)
      prepare_wizard
    end

    def edit
      prepare_wizard
    end

    def create
      @standup = Standup.new(standup_params)
      participant_rows = participant_rows_from_params

      if valid_standup_form?(participant_rows)
        participant_changes = []
        ActiveRecord::Base.transaction do
          @standup.save!
          @standup.standup_ownerships.create!(user: current_user, role: "owner") unless current_user.admin?
          participant_changes = apply_participant_rows!(@standup, participant_rows)
          audit_manager_change!(
            "standup.create",
            auditable: @standup,
            metadata: {
              attributes: audited_standup_attributes(@standup),
              participants: participant_changes
            }
          )
        end
        redirect_to manager_standup_path(@standup), status: :see_other
      else
        prepare_wizard(participant_rows: participant_rows)
        render :new, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => error
      @standup.errors.add(:base, error.record.errors.full_messages.to_sentence)
      prepare_wizard(participant_rows: participant_rows)
      render :new, status: :unprocessable_entity
    end

    def update
      @standup.assign_attributes(standup_params)
      participant_rows = participant_rows_from_params

      if valid_standup_form?(participant_rows)
        standup_changes = {}
        participant_changes = []
        ActiveRecord::Base.transaction do
          @standup.save!
          standup_changes = audited_changes(@standup)
          participant_changes = apply_participant_rows!(@standup, participant_rows)
          audit_manager_change!(
            "standup.update",
            auditable: @standup,
            metadata: {
              changes: standup_changes,
              participants: participant_changes
            }
          )
        end
        redirect_to manager_standup_path(@standup), status: :see_other
      else
        prepare_wizard(participant_rows: participant_rows)
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => error
      @standup.errors.add(:base, error.record.errors.full_messages.to_sentence)
      prepare_wizard(participant_rows: participant_rows)
      render :edit, status: :unprocessable_entity
    end

    def preview
      @standup = Standup.new(standup_params)
      @preview_timezone = preview_timezone_param
      prepare_schedule_preview

      render partial: "schedule_preview",
        locals: {
          occurrences: @schedule_preview,
          preview_timezone: @preview_timezone,
          schedule_preview_error: @schedule_preview_error
        }
    end

    def destroy
      snapshot = audited_standup_attributes(@standup)
      @standup.destroy!
      audit_manager_change!("standup.destroy", auditable: @standup, metadata: { attributes: snapshot })
      redirect_to manager_standups_path, status: :see_other
    end

    def pause
      change_active_state!(false, "standup.pause")
    end

    def resume
      change_active_state!(true, "standup.resume")
    end

    private

    def set_standup
      @standup = Standup.find(params[:id])
      authorize_standup!(@standup)
    end

    def standup_params
      permitted = params.require(:standup).permit(
        :name,
        :slack_channel,
        :intro,
        :outro,
        :schedule_type,
        :send_time,
        :monthly_day,
        :default_hour,
        :default_minute,
        :respect_timezone,
        :active,
        :reminder_enabled,
        :reminder_after_minutes,
        :max_reminders,
        :questions_text,
        :schedule_days_text,
        question_rows: [],
        questions: [],
        schedule_days: [],
        participants: [ :id, :slack_id, :slack_name, :cached_timezone, :active, :_destroy ]
      )
      attrs = permitted.to_h
      attrs.delete("participants")

      if attrs.key?("question_rows") || attrs.key?("questions_text") || attrs.key?("questions")
        attrs["questions"] = questions_from_attrs(attrs)
      end
      if attrs.key?("schedule_type") || attrs.key?("schedule_days") || attrs.key?("schedule_days_text") || attrs.key?("monthly_day")
        attrs["schedule_days"] = schedule_days_from_attrs(attrs)
      end
      apply_send_time!(attrs)

      attrs.delete("question_rows")
      attrs.delete("questions_text")
      attrs.delete("schedule_days_text")
      attrs.delete("monthly_day")
      attrs
    end

    def valid_standup_form?(participant_rows)
      standup_valid = @standup.valid?
      resolve_participant_rows(participant_rows)
      validate_participant_rows(participant_rows)
      standup_valid && @standup.errors.none?
    end

    def prepare_wizard(participant_rows: nil)
      @question_rows = padded_question_rows(Array(@standup.questions))
      @participant_rows = padded_participant_rows(participant_rows || participant_rows_for(@standup))
      @preview_timezone = preview_timezone_param
      @time_zone_options = ActiveSupport::TimeZone.all.map(&:name)
      prepare_schedule_preview
    end

    def prepare_schedule_preview
      @schedule_preview_error = nil
      @schedule_preview = build_schedule_preview(@standup, @preview_timezone || DEFAULT_PREVIEW_TIMEZONE)
    end

    def build_schedule_preview(standup, timezone)
      unless previewable_schedule?(standup)
        @schedule_preview_error = "Fix recurrence and send time to preview upcoming occurrences."
        return []
      end

      standup.upcoming_occurrences_in_timezone(timezone, count: PREVIEW_OCCURRENCE_COUNT)
    rescue StandardError => error
      Rails.logger.debug "Unable to preview standup schedule: #{error.class} - #{error.message}"
      @schedule_preview_error = "Fix recurrence and send time to preview upcoming occurrences."
      []
    end

    def previewable_schedule?(standup)
      Standup::SCHEDULE_TYPES.include?(standup.schedule_type) &&
        integer_in_range?(standup.default_hour, 0..23) &&
        integer_in_range?(standup.default_minute, 0..59) &&
        schedule_days_previewable?(standup)
    end

    def integer_in_range?(value, range)
      integer = Integer(value, exception: false)
      integer.present? && range.cover?(integer)
    end

    def schedule_days_previewable?(standup)
      days = Array(standup.schedule_days).reject(&:blank?)

      case standup.schedule_type
      when "custom"
        days.any? && days.all? { |day| integer_in_range?(day, 0..6) }
      when "weekly", "biweekly"
        days.empty? || days.all? { |day| integer_in_range?(day, 0..6) }
      when "monthly"
        days.empty? || days.all? { |day| integer_in_range?(day, 1..31) }
      else
        true
      end
    end

    def preview_timezone_param
      params[:preview_timezone].presence || DEFAULT_PREVIEW_TIMEZONE
    end

    def padded_question_rows(rows)
      normalized_rows = rows.map(&:to_s)
      normalized_rows += Array.new(BLANK_QUESTION_ROWS, "")
      normalized_rows
    end

    def padded_participant_rows(rows)
      rows + Array.new(BLANK_PARTICIPANT_ROWS) { blank_participant_row }
    end

    def participant_rows_for(standup)
      return [] unless standup.persisted?

      standup.standup_participants.order(:slack_name, :slack_id).map do |participant|
        {
          id: participant.id,
          slack_id: participant.slack_id,
          slack_name: participant.slack_name,
          cached_timezone: participant.cached_timezone,
          active: participant.active?,
          destroy: false
        }
      end
    end

    def participant_rows_from_params
      return [] unless params[:standup].present?

      raw_rows = params.require(:standup).permit(
        participants: [ :id, :slack_id, :slack_name, :cached_timezone, :active, :_destroy ]
      )[:participants]

      ordered_participant_rows(raw_rows).map { |row| sanitize_participant_row(row) }
    end

    def ordered_participant_rows(raw_rows)
      case raw_rows
      when ActionController::Parameters
        raw_rows.to_unsafe_h.sort_by { |index, _row| index.to_i }.map(&:last)
      when Hash
        raw_rows.sort_by { |index, _row| index.to_i }.map(&:last)
      when Array
        raw_rows
      else
        []
      end
    end

    def sanitize_participant_row(row)
      attributes = row.to_h
      slack_identifier = attributes["slack_id"].to_s.strip
      {
        id: attributes["id"].presence,
        slack_id: normalize_participant_identifier(slack_identifier),
        slack_name: attributes["slack_name"].to_s.strip,
        cached_timezone: attributes["cached_timezone"].to_s.strip.presence,
        active: boolean_param(attributes.key?("active") ? attributes["active"] : true),
        destroy: boolean_param(attributes["_destroy"])
      }
    end

    def validate_participant_rows(rows)
      seen_slack_ids = {}
      submitted_ids = rows.filter_map { |row| row[:id] }

      rows.each_with_index do |row, index|
        next if blank_participant_row?(row)

        row_label = "Participant #{index + 1}"
        if row[:id].present? && !@standup.standup_participants.exists?(id: row[:id])
          @standup.errors.add(:base, "#{row_label} could not be found for this standup")
          next
        end
        next if row[:destroy]

        @standup.errors.add(:base, "#{row_label} Slack ID can't be blank") if row[:slack_id].blank?
        @standup.errors.add(:base, "#{row_label} name can't be blank") if row[:slack_name].blank?

        if row[:slack_id].present? && !row[:slack_id].match?(StandupParticipant::SLACK_USER_ID_PATTERN)
          @standup.errors.add(:base, "#{row_label} Slack ID must look like U123ABC")
        end

        if row[:cached_timezone].present? && !StandupParticipant.valid_timezone?(row[:cached_timezone])
          @standup.errors.add(:base, "#{row_label} timezone is not valid")
        end

        next if row[:slack_id].blank?

        if seen_slack_ids.key?(row[:slack_id])
          @standup.errors.add(:base, "#{row_label} duplicates #{seen_slack_ids[row[:slack_id]]}")
        else
          seen_slack_ids[row[:slack_id]] = row_label
        end
      end

      validate_existing_participant_conflicts(rows, submitted_ids)
    end

    def validate_existing_participant_conflicts(rows, submitted_ids)
      return unless @standup.persisted?

      existing_slack_ids = @standup.standup_participants.where.not(id: submitted_ids).pluck(:slack_id)
      rows.each_with_index do |row, index|
        next if row[:destroy] || row[:slack_id].blank? || !existing_slack_ids.include?(row[:slack_id])

        @standup.errors.add(:base, "Participant #{index + 1} Slack ID is already in this standup")
      end
    end

    def normalize_participant_identifier(identifier)
      normalized = identifier.delete_prefix("@")
      upcased = normalized.upcase
      looks_like_id = (normalized == upcased && upcased.match?(StandupParticipant::SLACK_USER_ID_PATTERN)) ||
        upcased.match?(/\A[UW][A-Z0-9]*\d[A-Z0-9]*\z/)
      looks_like_id ? upcased : identifier
    end

    def resolve_participant_rows(rows)
      rows.each_with_index do |row, index|
        next if blank_participant_row?(row) || row[:destroy] || row[:slack_id].blank?
        next if row[:slack_id].match?(StandupParticipant::SLACK_USER_ID_PATTERN) && row[:slack_name].present?

        resolved_user = slack_user_resolver.resolve(row[:slack_id], fallback_name: row[:slack_name])
        row[:slack_id] = resolved_user.slack_id
        row[:slack_name] = row[:slack_name].presence || resolved_user.slack_name
        row[:cached_timezone] = row[:cached_timezone].presence || resolved_user.cached_timezone
      rescue SlackUserResolver::ResolutionError => error
        @standup.errors.add(:base, "Participant #{index + 1}: #{error.message}")
      end
    end

    def slack_user_resolver
      @slack_user_resolver ||= SlackUserResolver.new
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
      {
        slack_id: row[:slack_id],
        slack_name: row[:slack_name],
        cached_timezone: row[:cached_timezone],
        active: row[:active]
      }
    end

    def participant_snapshot(participant)
      participant.attributes.slice("id", "slack_id", "slack_name", "cached_timezone", "active")
    end

    def participant_change(action, participant, before: nil)
      payload = participant_snapshot(participant).merge(action: action)
      payload[:before] = before if before
      payload
    end

    def blank_participant_row
      { id: nil, slack_id: "", slack_name: "", cached_timezone: "", active: true, destroy: false }
    end

    def blank_participant_row?(row)
      row[:id].blank? &&
        row[:slack_id].blank? &&
        row[:slack_name].blank? &&
        row[:cached_timezone].blank?
    end

    def boolean_param(value)
      ActiveModel::Type::Boolean.new.cast(value)
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

    def dashboard_visibility
      params.fetch(:visibility, "all").presence_in(%w[all active paused]) || "all"
    end

    def dashboard_period_days
      params.fetch(:period_days, StandupDashboard::DEFAULT_PERIOD_DAYS).to_i.clamp(1, 90)
    end

    def filtered_standups
      scope = manageable_standups.includes(:standup_participants, :standup_responses)

      case @visibility
      when "active"
        scope.active
      when "paused"
        scope.where(active: false)
      else
        scope
      end
    end

    def change_active_state!(active, action)
      previous_active = @standup.active?

      if previous_active != active
        @standup.update!(active: active)
        audit_manager_change!(
          action,
          auditable: @standup,
          metadata: { changes: { active: [ previous_active, active ] } }
        )
      end

      redirect_back fallback_location: manager_standups_path, status: :see_other
    end

    def split_lines(value)
      value.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def split_numbers(value)
      value.to_s.split(/[,\s]+/).reject(&:blank?)
    end

    def audited_changes(standup)
      standup.saved_changes.except("updated_at").transform_values { |before, after| [ before, after ] }
    end

    def audited_standup_attributes(standup)
      standup.attributes.slice(
        "id",
        "name",
        "slack_channel",
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

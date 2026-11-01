module Api
  # Skipped, holiday, cancelled, and moved runs, plus a preview of upcoming
  # runs (in `?preview_timezone=`, UTC by default).
  class StandupScheduleExceptionsController < BaseController
    UPCOMING_OCCURRENCE_COUNT = 8
    DEFAULT_EXCEPTION_TIMEZONE = "UTC"
    EXCEPTION_TYPE_OPTIONS = [
      { value: "skipped_date", label: "Skipped date" },
      { value: "holiday", label: "Holiday" }
    ].freeze
    NOTES = [
      "Skipped, holiday, and canceled dates do not create prompts, reminders, or expected report rows.",
      "Moved runs replace the original send time and reminders follow the new time, while responses and reports stay attached to the original standup date."
    ].freeze

    before_action :require_manager!
    before_action :set_standup
    before_action :set_schedule_exception, only: :destroy

    def index
      preview_timezone = preview_timezone_param
      upcoming_occurrences = @standup.upcoming_occurrence_details_in_timezone(
        preview_timezone,
        count: UPCOMING_OCCURRENCE_COUNT,
        include_blocked: true
      )
      next_occurrence = @standup.next_occurrence_detail_in_timezone(preview_timezone)

      render json: {
        standup: StandupSerializer.new(@standup).as_json,
        preview_timezone: preview_timezone,
        default_exception_timezone: DEFAULT_EXCEPTION_TIMEZONE,
        time_zone_options: ActiveSupport::TimeZone.all.map(&:name),
        exception_type_options: EXCEPTION_TYPE_OPTIONS,
        upcoming_occurrences: upcoming_occurrences.map { |occurrence| serialize_occurrence(occurrence, preview_timezone) },
        next_occurrence: (serialize_occurrence(next_occurrence, preview_timezone) if next_occurrence),
        schedule_exceptions: @standup.standup_schedule_exceptions.upcoming_first.map { |schedule_exception| serialize_exception(schedule_exception) },
        notes: NOTES
      }
    end

    def create
      schedule_exception = @standup.standup_schedule_exceptions.new(schedule_exception_params)

      if schedule_exception.save
        audit_change!(
          audit_action_for(schedule_exception),
          auditable: @standup,
          metadata: { schedule_exception: schedule_exception_snapshot(schedule_exception) }
        )
        render json: {
          schedule_exception: serialize_exception(schedule_exception),
          notice: "#{schedule_exception.label} saved for #{schedule_exception.original_date.to_fs(:long)}."
        }, status: :created
      else
        render_validation_errors(schedule_exception.errors)
      end
    end

    def destroy
      snapshot = schedule_exception_snapshot(@schedule_exception)
      payload = serialize_exception(@schedule_exception)
      @schedule_exception.destroy!
      audit_change!(
        "standup.schedule_exception.remove",
        auditable: @standup,
        metadata: { schedule_exception: snapshot }
      )
      render json: {
        schedule_exception: payload,
        notice: "Removed the #{@schedule_exception.label.downcase} exception for #{@schedule_exception.original_date.to_fs(:long)}."
      }
    end

    private

    def set_schedule_exception
      @schedule_exception = @standup.standup_schedule_exceptions.find(params[:id])
    end

    def schedule_exception_params
      permitted = params.require(:schedule_exception).permit(
        :exception_type,
        :original_date,
        :rescheduled_date,
        :rescheduled_time,
        :rescheduled_timezone,
        :reason
      )

      permitted[:rescheduled_timezone] ||= DEFAULT_EXCEPTION_TIMEZONE if permitted[:exception_type] == "rescheduled"
      permitted
    end

    def preview_timezone_param
      requested_timezone = params[:preview_timezone].presence || DEFAULT_EXCEPTION_TIMEZONE
      StandupParticipant.valid_timezone?(requested_timezone) ? requested_timezone : DEFAULT_EXCEPTION_TIMEZONE
    end

    def audit_action_for(schedule_exception)
      case schedule_exception.exception_type
      when "rescheduled"
        "standup.schedule_exception.reschedule"
      when "cancelled"
        "standup.schedule_exception.cancel"
      when "holiday"
        "standup.schedule_exception.holiday"
      else
        "standup.schedule_exception.skip"
      end
    end

    def schedule_exception_snapshot(schedule_exception)
      {
        id: schedule_exception.id,
        exception_type: schedule_exception.exception_type,
        original_date: schedule_exception.original_date&.iso8601,
        rescheduled_date: schedule_exception.rescheduled_date&.iso8601,
        rescheduled_hour: schedule_exception.rescheduled_hour,
        rescheduled_minute: schedule_exception.rescheduled_minute,
        rescheduled_timezone: schedule_exception.rescheduled_timezone,
        reason: schedule_exception.reason
      }
    end

    def serialize_occurrence(occurrence, timezone)
      ScheduleExceptionOccurrenceSerializer.new(occurrence, timezone: timezone).as_json
    end

    def serialize_exception(schedule_exception)
      ScheduleExceptionSerializer.new(schedule_exception).as_json
    end
  end
end

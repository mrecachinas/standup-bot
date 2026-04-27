module Manager
  class StandupScheduleExceptionsController < ApplicationController
    before_action :set_standup
    before_action :set_schedule_exception, only: :destroy

    UPCOMING_OCCURRENCE_COUNT = 8
    DEFAULT_EXCEPTION_TIMEZONE = "UTC"

    def index
      @schedule_exception = @standup.standup_schedule_exceptions.new
      prepare_schedule_exceptions
    end

    def create
      @schedule_exception = @standup.standup_schedule_exceptions.new(schedule_exception_params)

      if @schedule_exception.save
        audit_manager_change!(
          audit_action_for(@schedule_exception),
          auditable: @standup,
          metadata: { schedule_exception: schedule_exception_snapshot(@schedule_exception) }
        )
        redirect_to manager_standup_schedule_exceptions_path(@standup), status: :see_other
      else
        prepare_schedule_exceptions
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      snapshot = schedule_exception_snapshot(@schedule_exception)
      @schedule_exception.destroy!
      audit_manager_change!(
        "standup.schedule_exception.remove",
        auditable: @standup,
        metadata: { schedule_exception: snapshot }
      )
      redirect_to manager_standup_schedule_exceptions_path(@standup), status: :see_other
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def set_schedule_exception
      @schedule_exception = @standup.standup_schedule_exceptions.find(params[:id])
    end

    def prepare_schedule_exceptions
      @preview_timezone = preview_timezone_param
      @time_zone_options = ActiveSupport::TimeZone.all.map(&:name)
      @default_exception_timezone = DEFAULT_EXCEPTION_TIMEZONE
      @upcoming_occurrences = @standup.upcoming_occurrence_details_in_timezone(
        @preview_timezone,
        count: UPCOMING_OCCURRENCE_COUNT,
        include_blocked: true
      )
      @next_occurrence = @standup.next_occurrence_detail_in_timezone(@preview_timezone)
      @schedule_exceptions = @standup.standup_schedule_exceptions.upcoming_first
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
  end
end

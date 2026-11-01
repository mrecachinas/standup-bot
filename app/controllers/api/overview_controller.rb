module Api
  # The console's home page across every standup the caller manages.
  class OverviewController < BaseController
    before_action :require_manager!
    before_action :skip_authorization

    VISIBILITIES = %w[all active paused].freeze

    def show
      visibility = params.fetch(:visibility, "all").presence_in(VISIBILITIES) || "all"
      days = params.fetch(:period_days, Manager::StandupDashboard::DEFAULT_PERIOD_DAYS).to_i.clamp(1, 90)
      standups = filtered_standups(visibility).order(:name)
      dashboard = Manager::StandupDashboard.new(standups, period_days: days)

      render json: OverviewDashboardSerializer.new(dashboard, visibility: visibility, period_days: days).as_json
    end

    private

    def filtered_standups(visibility)
      scope = manageable_standups.includes(:standup_participants, :standup_schedule_exceptions)

      case visibility
      when "active" then scope.active
      when "paused" then scope.where(active: false)
      else scope
      end
    end
  end
end

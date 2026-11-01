module Api
  class StandupStatsController < BaseController
    before_action :require_manager!
    before_action :set_standup

    def show
      analytics = StandupAnalyticsService.new(@standup, period_days: period_days)
      render json: { stats: analytics.summary }
    end
  end
end

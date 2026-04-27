module Api
  class StandupStatsController < BaseController
    before_action :set_standup

    def show
      analytics = StandupAnalyticsService.new(@standup, period_days: period_days)
      render json: { stats: analytics.summary }
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
    end

    def period_days
      params.fetch(:period_days, 30).to_i.clamp(1, 365)
    end
  end
end

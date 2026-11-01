module Api
  class StandupAnalyticsController < BaseController
    before_action :set_standup

    def show
      analytics = StandupAnalyticsService.new(@standup, period_days: period_days)
      render json: {
        analytics: analytics.summary.merge(
          response_trends: analytics.response_trends,
          blocker_keywords: analytics.blocker_keywords(limit: 10)
        )
      }
    end
  end
end

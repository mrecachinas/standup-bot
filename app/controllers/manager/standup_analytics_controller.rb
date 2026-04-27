module Manager
  class StandupAnalyticsController < ApplicationController
    before_action :set_standup

    def show
      @analytics = StandupAnalyticsService.new(@standup, **analytics_options)

      respond_to do |format|
        format.html do
          @summary = @analytics.summary
          @response_trends = @analytics.response_trends
          @frequent_non_responders = @analytics.frequent_non_responders(limit: 5)
          @question_summaries = @analytics.question_summaries(limit: 3)
          @blocker_keywords = @analytics.blocker_keywords(limit: 10)
        end
        format.csv do
          send_data @analytics.to_csv,
            filename: "#{@standup.name.parameterize}-analytics-#{@analytics.start_date.iso8601}-#{@analytics.end_date.iso8601}.csv",
            type: "text/csv; charset=utf-8",
            disposition: "attachment"
        end
      end
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def analytics_options
      {
        period_days: params.fetch(:period_days, StandupAnalyticsService::DEFAULT_PERIOD_DAYS).to_i.clamp(1, StandupAnalyticsService::MAX_RANGE_DAYS),
        start_date: analytics_params[:start_date],
        end_date: analytics_params[:end_date]
      }
    end

    def analytics_params
      params.permit(:period_days, :start_date, :end_date)
    end
  end
end

module Api
  # The standup's analytics. Without options this is the admin API's
  # `{ analytics: ... }` payload for the last `period_days`. `?view=insights`
  # adds what the console's Insights tab draws, for a start_date/end_date
  # range, and `.csv` downloads the per-person export.
  class StandupAnalyticsController < BaseController
    before_action :require_manager!
    before_action :set_standup

    def show
      if request.format.csv?
        export_csv
      elsif params[:view] == "insights"
        render_insights
      else
        analytics = StandupAnalyticsService.new(@standup, period_days: period_days)
        render json: { analytics: analytics_payload(analytics) }
      end
    end

    private

    def set_standup
      @standup = Standup.includes(:standup_schedule_exceptions).find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def render_insights
      analytics = StandupAnalyticsService.new(@standup, **analytics_options)
      render json: {
        analytics: analytics_payload(analytics),
        standup: StandupSerializer.new(@standup, include_counts: true).as_json,
        insights: AnalyticsInsightsSerializer.new(analytics, previous: previous_period_analytics(analytics)).as_json,
        csv_path: api_standup_analytics_path(@standup, format: :csv, start_date: analytics.start_date.iso8601, end_date: analytics.end_date.iso8601)
      }
    end

    def export_csv
      analytics = StandupAnalyticsService.new(@standup, **analytics_options)
      send_data analytics.to_csv,
        filename: "#{@standup.name.parameterize}-analytics-#{analytics.start_date.iso8601}-#{analytics.end_date.iso8601}.csv",
        type: "text/csv; charset=utf-8",
        disposition: "attachment"
    end

    def analytics_payload(analytics)
      analytics.summary.merge(
        response_trends: analytics.response_trends,
        blocker_keywords: analytics.blocker_keywords(limit: 10)
      )
    end

    def previous_period_analytics(analytics)
      span = (analytics.end_date - analytics.start_date).to_i + 1
      StandupAnalyticsService.new(@standup, start_date: analytics.start_date - span, end_date: analytics.start_date - 1)
    end

    def analytics_options
      {
        period_days: period_days,
        start_date: params[:start_date].presence&.to_s,
        end_date: params[:end_date].presence&.to_s
      }
    end
  end
end

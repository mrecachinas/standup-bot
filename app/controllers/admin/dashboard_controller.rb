module Admin
  class DashboardController < Web::ApplicationController
    ACTIVITY_DAYS = 14

    before_action :authenticate_user!
    before_action :require_admin!

    def show
      @health = HealthCheckService.call
      @metrics = HealthCheckService.metrics
      @users = User.includes(:identities).order(:name).to_a
      @owned_standup_counts = StandupOwnership.group(:user_id).count
      @audit_logs = AuditLog.includes(:actor).recent.limit(15)
      @failed_reports = ReportGeneration.includes(:standup).where(status: "failed").recent.limit(5)
      @daily_activity = daily_activity
    end

    private

    def daily_activity
      dates = ((ACTIVITY_DAYS - 1).days.ago.to_date..Date.current).to_a
      counts = StandupResponse.where(standup_date: dates.first..dates.last).group(:standup_date, :status).count

      dates.filter_map do |date|
        by_status = counts.select { |(day, _status), _count| day == date }.transform_keys(&:last)
        total = by_status.values.sum
        next if total.zero?

        completed = by_status["completed"].to_i
        {
          date: date,
          expected: total,
          completed: completed,
          skipped: by_status["skipped"].to_i,
          pending: by_status["pending"].to_i,
          missed: by_status["expired"].to_i + by_status["cancelled"].to_i,
          completion_rate: (completed * 100.0 / total).round(1)
        }
      end
    end
  end
end

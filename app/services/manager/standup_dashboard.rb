module Manager
  class StandupDashboard
    DEFAULT_PERIOD_DAYS = 14

    def initialize(standups, period_days: DEFAULT_PERIOD_DAYS, now: Time.current)
      @standups = standups
      @period_days = period_days.to_i.clamp(1, 90)
      @now = now
    end

    def items
      @items ||= standups.map { |standup| Item.new(standup, period_days: period_days, now: now) }
    end

    # Team-wide totals per calendar date across every standup on the dashboard.
    def daily_totals
      totals = Hash.new { |hash, date| hash[date] = { date: date, expected: 0, completed: 0, skipped: 0, pending: 0, missed: 0 } }
      items.each do |item|
        item.runs.each do |run|
          %i[expected completed skipped pending missed].each { |key| totals[run[:date]][key] += run[key] }
        end
      end
      totals.values.sort_by { |row| row[:date] }.map do |row|
        row.merge(completion_rate: row[:expected].zero? ? 0.0 : (row[:completed] * 100.0 / row[:expected]).round(1))
      end
    end

    class Item
      attr_reader :standup, :period_days

      def initialize(standup, period_days:, now:)
        @standup = standup
        @period_days = period_days
        @now = now
      end

      def participant_count
        participant_names.size
      end

      def participant_names
        @participant_names ||= standup.standup_participants.active.order(:slack_name).pluck(:slack_name, :slack_id)
          .map { |name, slack_id| name.presence || slack_id }
      end

      def runs
        @runs ||= analytics.run_breakdown
      end

      def trend_rates
        runs.map { |run| run[:completion_rate] }
      end

      def next_occurrence
        return unless standup.active?

        @next_occurrence ||= standup.next_occurrence_detail_in_timezone("UTC", from: now)
      rescue StandardError
        nil
      end

      def needs_attention?
        !standup.active? || participant_count.zero? || (expected_responses.positive? && completion_rate < 60)
      end

      def attention_reason
        return "Paused" unless standup.active?
        return "No active participants" if participant_count.zero?

        "#{completion_rate.round}% completion over #{period_days} days"
      end

      def status_label
        standup.active? ? "Active" : "Paused"
      end

      def completion_rate
        summary[:completion_rate]
      end

      def completed_responses
        summary[:completed_responses]
      end

      def expected_responses
        summary[:expected_responses]
      end

      def latest_run_status
        return "No runs yet" unless latest_run_response
        return "Pending" if latest_run_status_counts["pending"].to_i.positive?
        return "Completed" if latest_run_status_counts["completed"].to_i.positive? && latest_run_status_counts.except("completed").empty?

        latest_run_status_counts.keys.map(&:titleize).to_sentence
      end

      def latest_run_summary
        return unless latest_run_response

        counts = latest_run_status_counts
        answered = counts["completed"].to_i
        total = counts.values.sum
        "#{latest_run_date.strftime("%b %-d")} · #{answered} of #{total} answered"
      end

      private

      attr_reader :now

      def summary
        @summary ||= analytics.summary
      end

      def analytics
        @analytics ||= StandupAnalyticsService.new(standup, period_days: period_days, now: now)
      end

      def latest_run_response
        @latest_run_response ||= standup.standup_responses.order(created_at: :desc).first
      end

      def latest_run_date
        latest_run_response.standup_date || latest_run_response.created_at.to_date
      end

      def latest_run_status_counts
        @latest_run_status_counts ||= latest_run_responses.group(:status).count
      end

      def latest_run_responses
        dated_responses = standup.standup_responses.where(standup_date: latest_run_date)
        legacy_responses = standup.standup_responses.where(
          standup_date: nil,
          created_at: latest_run_date.beginning_of_day..latest_run_date.end_of_day
        )

        dated_responses.or(legacy_responses)
      end
    end

    private

    attr_reader :standups, :period_days, :now
  end
end

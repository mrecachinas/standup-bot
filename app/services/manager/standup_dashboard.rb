module Manager
  class StandupDashboard
    DEFAULT_PERIOD_DAYS = 14
    WEEKDAY_NAMES = Date::DAYNAMES.dup.freeze

    def initialize(standups, period_days: DEFAULT_PERIOD_DAYS, now: Time.current)
      @standups = standups
      @period_days = period_days.to_i.clamp(1, 90)
      @now = now
    end

    def items
      standups.map { |standup| Item.new(standup, period_days: period_days, now: now) }
    end

    class Item
      attr_reader :standup, :period_days

      def initialize(standup, period_days:, now:)
        @standup = standup
        @period_days = period_days
        @now = now
      end

      def participant_count
        standup.standup_participants.active.count
      end

      def status_label
        standup.active? ? "Active" : "Paused"
      end

      def cadence_label
        "#{schedule_label} at #{scheduled_time_label}"
      end

      def timezone_label
        return "UTC" unless standup.respect_timezone?

        cached_timezones = standup.standup_participants.active
          .where.not(cached_timezone: [ nil, "" ])
          .distinct
          .pluck(:cached_timezone)

        cached_timezones.any? ? cached_timezones.to_sentence : "Participant timezones"
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

      def latest_run_detail
        return "No responses have been collected yet" unless latest_run_response

        "#{latest_run_date.to_fs(:medium)} · #{latest_run_status_counts.map { |status, count| "#{count} #{status}" }.join(", ")}"
      end

      private

      attr_reader :now

      def summary
        @summary ||= StandupAnalyticsService.new(standup, period_days: period_days, now: now).summary
      end

      def schedule_label
        case standup.schedule_type
        when "daily"
          "Daily"
        when "weekdays"
          "Weekdays"
        when "weekly"
          "Weekly #{weekday_names.to_sentence}"
        when "biweekly"
          "Biweekly #{weekday_names.to_sentence}"
        when "monthly"
          "Monthly day #{schedule_days.first || 1}"
        when "custom"
          "Custom #{weekday_names.to_sentence}"
        else
          standup.schedule_type.to_s.titleize
        end
      end

      def scheduled_time_label
        format("%02d:%02d", standup.default_hour, standup.default_minute)
      end

      def weekday_names
        schedule_days.map { |day| WEEKDAY_NAMES[day] }.compact
      end

      def schedule_days
        @schedule_days ||= Array(standup.schedule_days).filter_map { |day| Integer(day, exception: false) }
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

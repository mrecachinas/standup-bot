require "benchmark"

class HealthCheckService
  QUEUE_TABLES = {
    ready: "solid_queue_ready_executions",
    scheduled: "solid_queue_scheduled_executions",
    failed: "solid_queue_failed_executions"
  }.freeze

  MissingQueueTable = Class.new(StandardError)

  class << self
    def call
      checks = {
        database: database_check,
        job_queue: job_queue_check,
        slack_api: slack_check
      }

      {
        status: overall_status(checks),
        timestamp: Time.current.iso8601,
        checks: checks
      }
    end

    def metrics
      {
        timestamp: Time.current.iso8601,
        standups: {
          active: Standup.active.count,
          inactive: Standup.where(active: false).count,
          participants: StandupParticipant.count,
          active_participants: StandupParticipant.active.count
        },
        responses: StandupResponse.group(:status).count,
        recent_activity: {
          responses_last_24h: StandupResponse.where("created_at >= ?", 24.hours.ago).count,
          completed_last_24h: StandupResponse.completed.where("created_at >= ?", 24.hours.ago).count
        }
      }
    end

    private

    def database_check
      latency = Benchmark.realtime do
        ActiveRecord::Base.connection.execute("SELECT 1")
      end

      {
        status: "ok",
        adapter: ActiveRecord::Base.connection.adapter_name,
        latency_ms: (latency * 1000).round(2)
      }
    rescue StandardError => e
      { status: "error", error: e.class.name, message: e.message }
    end

    def job_queue_check
      return non_solid_queue_check unless solid_queue_adapter?

      ready_jobs = count_queue_table(QUEUE_TABLES[:ready])
      scheduled_jobs = count_queue_table(QUEUE_TABLES[:scheduled])
      failed_jobs = count_queue_table(QUEUE_TABLES[:failed])

      {
        status: "ok",
        adapter: queue_adapter_name,
        configured: true,
        database: queue_database_name,
        pending_jobs: ready_jobs + scheduled_jobs,
        failed_jobs: failed_jobs
      }
    rescue StandardError => e
      {
        status: "warn",
        adapter: queue_adapter_name,
        configured: solid_queue_adapter?,
        database: queue_database_name,
        error: e.class.name,
        message: e.message
      }
    end

    def slack_check
      configured = Rails.application.config.slack[:bot_token].present?
      {
        status: configured ? "ok" : "warn",
        configured: configured,
        last_successful_message_at: StandupMetrics.last_seen("slack.message_sent"),
        last_rate_limited_at: StandupMetrics.last_seen("slack.rate_limited")
      }
    end

    def non_solid_queue_check
      {
        status: "ok",
        adapter: queue_adapter_name,
        configured: false,
        pending_jobs: nil,
        failed_jobs: nil
      }
    end

    def solid_queue_adapter?
      queue_adapter_name == "solid_queue"
    end

    def queue_adapter_name
      ActiveJob::Base.queue_adapter_name.to_s
    rescue StandardError
      ActiveJob::Base.queue_adapter.class.name
    end

    def count_queue_table(table_name)
      unless QUEUE_TABLES.value?(table_name)
        raise ArgumentError, "unsupported Solid Queue table: #{table_name}"
      end

      connection = solid_queue_connection
      unless connection.data_source_exists?(table_name)
        raise MissingQueueTable, "Solid Queue table #{table_name} is not available on #{queue_database_name}"
      end

      quoted_table_name = connection.quote_table_name(table_name)
      connection.select_value("SELECT COUNT(*) FROM #{quoted_table_name}").to_i
    end

    def solid_queue_connection
      SolidQueue::Record.connection
    end

    def queue_database_name
      SolidQueue::Record.connection_db_config.name
    rescue StandardError
      "unknown"
    end

    def overall_status(checks)
      statuses = checks.values.map { |check| check[:status] }
      return "unhealthy" if statuses.include?("error")
      return "degraded" if statuses.include?("warn")

      "healthy"
    end
  end
end

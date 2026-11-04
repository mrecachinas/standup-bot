# Readiness for bin/jobs in Kubernetes (config/kubernetes/production): with
# SOLID_QUEUE_READY_FILE set, each worker touches that file every 15 seconds
# while its own process record is registered and heartbeating, so a pod
# counts as ready only once it can actually run jobs.
if (ready_file = ENV["SOLID_QUEUE_READY_FILE"].presence)
  SolidQueue.on_worker_start do |worker|
    Thread.new do
      loop do
        alive = Rails.application.executor.wrap do
          SolidQueue::Process.where(id: worker.process_id)
            .where(last_heartbeat_at: (SolidQueue.process_heartbeat_interval * 2).ago..).exists?
        end
        FileUtils.touch(ready_file) if alive
      rescue StandardError => error
        Rails.logger.warn "Solid Queue readiness check failed: #{error.class} - #{error.message}"
      ensure
        sleep 15
      end
    end
  end
end

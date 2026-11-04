require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class FailingJob < ApplicationJob
    def perform = raise(ArgumentError, "bad input")
  end

  class ContextJob < ApplicationJob
    cattr_accessor :seen_context

    def perform = self.class.seen_context = Instrumentation.context.dup
  end

  class RetryingJob < ApplicationJob
    def perform = raise(Net::ReadTimeout)
  end

  class InnerJob < ApplicationJob
    def perform(fail:) = fail ? raise(ArgumentError, "inner failed") : :done
  end

  class OuterJob < ApplicationJob
    cattr_accessor :seen

    def perform
      self.class.seen = []
      InnerJob.perform_now(fail: false)
      record_context
      begin
        InnerJob.perform_now(fail: true)
      rescue ArgumentError
        record_context
      end
    end

    private

    def record_context
      self.class.seen << [ Instrumentation.context.dup, ActiveSupport::ExecutionContext.to_h ]
    end
  end

  class ErrorCollector
    attr_reader :reports

    def initialize = @reports = []
    def report(error, **details) = @reports << details.merge(error: error)
  end

  setup do
    @previous_admin_channel = ENV["ADMIN_CHANNEL"]
    ENV["ADMIN_CHANNEL"] = "C-ADMIN"
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    ENV["ADMIN_CHANNEL"] = @previous_admin_channel
    Rails.cache = @previous_cache
  end

  test "posts one notice per kind of failure in a while, not one per failure" do
    ChatPlatform::SlackAdapter.any_instance.expects(:send_message)
      .with("C-ADMIN", regexp_matches(/\A⚠️ Job ApplicationJobTest::FailingJob failed: ArgumentError - bad input \(similar failures are muted for 15 minutes\)/))
      .once

    3.times { assert_raises(ArgumentError) { FailingJob.perform_now } }
  end

  test "a cache failure doesn't hide the job's own error or stop the notice" do
    Rails.cache.stubs(:increment).raises(ActiveRecord::ConnectionNotEstablished, "cache database down")
    ChatPlatform::SlackAdapter.any_instance.expects(:send_message).with("C-ADMIN", regexp_matches(/bad input/)).once

    assert_raises(ArgumentError) { FailingJob.perform_now }
  end

  test "tracks failures by error class, without the error message" do
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_message)
    StandupMetrics.expects(:track).with do |event, tags|
      event == "job.failed" && tags[:job_class] == "ApplicationJobTest::FailingJob" &&
        tags[:error_class] == "ArgumentError" && !tags.key?(:error_message)
    end

    assert_raises(ArgumentError) { FailingJob.perform_now }
  end

  test "sets the job's instrumentation context" do
    job = ContextJob.new
    job.perform_now

    assert_equal({ job_class: "ApplicationJobTest::ContextJob", job_id: job.job_id, queue: "default" }, ContextJob.seen_context.slice(:job_class, :job_id, :queue))
  end

  test "a job run inside another puts the outer job's context back, even when it fails" do
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_message)
    outer = OuterJob.new
    outer.perform_now

    expected = { job_class: "ApplicationJobTest::OuterJob", job_id: outer.job_id, queue: "default" }
    assert_equal 2, OuterJob.seen.size
    OuterJob.seen.each do |event_context, error_context|
      assert_equal expected, event_context.slice(:job_class, :job_id, :queue)
      assert_equal expected, error_context.slice(:job_class, :job_id, :queue)
      assert_same outer, error_context[:job]
    end
  end

  test "reports a failure with the failing job's context" do
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_message)
    collector = ErrorCollector.new
    Rails.error.subscribe(collector)
    job = FailingJob.new

    assert_raises(ArgumentError) { job.perform_now }

    report = collector.reports.sole
    assert_equal "bad input", report[:error].message
    assert_equal false, report[:handled]
    assert_equal "application.active_job", report[:source]
    assert_equal({ job_class: "ApplicationJobTest::FailingJob", job_id: job.job_id, queue: "default" }, report[:context].slice(:job_class, :job_id, :queue))
  ensure
    Rails.error.unsubscribe(collector)
  end

  test "doesn't report errors that retry_on handles" do
    collector = ErrorCollector.new
    Rails.error.subscribe(collector)
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_message)

    assert_enqueued_with(job: RetryingJob) { RetryingJob.perform_now }

    assert_empty collector.reports
  ensure
    Rails.error.unsubscribe(collector)
  end
end

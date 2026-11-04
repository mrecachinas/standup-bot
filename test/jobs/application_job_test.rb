require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class FailingJob < ApplicationJob
    def perform = raise(ArgumentError, "bad input")
  end

  class ContextJob < ApplicationJob
    cattr_accessor :seen_context

    def perform = self.class.seen_context = Instrumentation.context.dup
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
end

require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class FailingJob < ApplicationJob
    def perform = raise(ArgumentError, "bad input")
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
end

require "test_helper"

class ReportGenerationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @standup = standups(:daily)
    @manager = users(:manager)
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "creates generation history and enqueues collection job from saved configuration" do
    configuration = report_configurations(:daily_report)

    assert_difference "ReportGeneration.count", 1 do
      assert_enqueued_jobs 1 do
        @result = ReportGenerationService.new(standup: @standup, actor: @manager).call
      end
    end

    assert @result.success?
    generation = @result.report_generation
    assert_equal "queued", generation.status
    assert_equal configuration, generation.report_configuration
    assert_equal @manager, generation.actor
    assert_equal "daily-reports", generation.delivery_channel
    assert_equal [ "UREPORT1" ], generation.recipients
    assert_equal "detailed", generation.detail_level
    assert_equal StandupCollectionJob, enqueued_jobs.last[:job]
  end

  test "uses standup channel as safe default when configuration has not been saved" do
    report_configurations(:daily_report).destroy!

    assert_enqueued_jobs 1 do
      @result = ReportGenerationService.new(standup: @standup.reload, actor: @manager).call
    end

    assert @result.success?
    assert_equal @standup.slack_channel, @result.report_generation.delivery_channel
    assert_nil @result.report_generation.report_configuration
  end

  test "records failed history when the job cannot be queued" do
    StandupCollectionJob.expects(:perform_later).raises(StandardError.new("queue unavailable"))

    assert_difference "ReportGeneration.count", 1 do
      @result = ReportGenerationService.new(standup: @standup, actor: @manager).call
    end

    assert_not @result.success?
    generation = @result.report_generation
    assert generation.failed?
    assert_includes generation.error_message, "queue unavailable"
  end

  test "records invalid configuration as failed generation without enqueueing" do
    configuration = report_configurations(:daily_report)
    configuration.update_column(:delivery_channel, "")

    assert_no_enqueued_jobs do
      @result = ReportGenerationService.new(standup: @standup.reload, actor: @manager).call
    end

    assert_not @result.success?
    assert @result.report_generation.failed?
    assert_equal "unconfigured", @result.report_generation.delivery_channel
    assert_includes @result.message, "Report configuration is invalid"
  end
end

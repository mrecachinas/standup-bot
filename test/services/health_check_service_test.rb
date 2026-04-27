require "test_helper"

class HealthCheckServiceTest < ActiveSupport::TestCase
  FakeQueueConnection = Struct.new(:counts) do
    def data_source_exists?(table_name)
      counts.key?(table_name)
    end

    def quote_table_name(table_name)
      "`#{table_name}`"
    end

    def select_value(sql)
      table_name = sql[/`([^`]+)`/, 1]
      counts.fetch(table_name)
    end
  end

  test "job queue check skips metrics when Solid Queue is not configured" do
    ActiveJob::Base.stubs(:queue_adapter_name).returns(:async)
    HealthCheckService.expects(:solid_queue_connection).never

    check = HealthCheckService.send(:job_queue_check)

    assert_equal "ok", check[:status]
    assert_equal "async", check[:adapter]
    assert_equal false, check[:configured]
    assert_nil check[:pending_jobs]
    assert_nil check[:failed_jobs]
  end

  test "job queue check counts Solid Queue tables through the queue connection" do
    ActiveJob::Base.stubs(:queue_adapter_name).returns(:solid_queue)
    HealthCheckService.stubs(:queue_database_name).returns("queue")
    HealthCheckService.stubs(:solid_queue_connection).returns(
      FakeQueueConnection.new({
        "solid_queue_ready_executions" => 3,
        "solid_queue_scheduled_executions" => 2,
        "solid_queue_failed_executions" => 1
      })
    )
    ActiveRecord::Base.connection.expects(:select_value).never

    check = HealthCheckService.send(:job_queue_check)

    assert_equal "ok", check[:status]
    assert_equal "solid_queue", check[:adapter]
    assert_equal true, check[:configured]
    assert_equal "queue", check[:database]
    assert_equal 5, check[:pending_jobs]
    assert_equal 1, check[:failed_jobs]
  end

  test "job queue check warns when a Solid Queue table is missing" do
    ActiveJob::Base.stubs(:queue_adapter_name).returns(:solid_queue)
    HealthCheckService.stubs(:queue_database_name).returns("queue")
    HealthCheckService.stubs(:solid_queue_connection).returns(
      FakeQueueConnection.new({
        "solid_queue_ready_executions" => 3,
        "solid_queue_failed_executions" => 1
      })
    )

    check = HealthCheckService.send(:job_queue_check)

    assert_equal "warn", check[:status]
    assert_equal "solid_queue", check[:adapter]
    assert_equal true, check[:configured]
    assert_equal "queue", check[:database]
    assert_equal "HealthCheckService::MissingQueueTable", check[:error]
    assert_match "solid_queue_scheduled_executions", check[:message]
  end
end

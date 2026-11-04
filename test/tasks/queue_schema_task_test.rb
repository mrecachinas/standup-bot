require "test_helper"
require "rake"

class QueueSchemaTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("standups:validate")
  end

  test "schema dumps skip the development queue database" do
    queue = ActiveRecord::DatabaseConfigurations::HashConfig.new(
      "development", "queue", { adapter: "mysql2", database: "standupbot_development_queue" }
    )
    ActiveRecord::Tasks::DatabaseTasks.expects(:with_temporary_pool).never

    assert_nil ActiveRecord::Tasks::DatabaseTasks.dump_schema(queue)
  end

  test "schema dumps still run for the development primary database" do
    primary = ActiveRecord::DatabaseConfigurations::HashConfig.new(
      "development", "primary", { adapter: "mysql2", database: "standupbot_development" }
    )
    ActiveRecord::Tasks::DatabaseTasks.expects(:with_temporary_pool).with(primary).once

    ActiveRecord::Tasks::DatabaseTasks.dump_schema(primary)
  end
end

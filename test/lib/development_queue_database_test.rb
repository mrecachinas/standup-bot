require "test_helper"
require Rails.root.join("lib/development_queue_database").to_s

class DevelopmentQueueDatabaseTest < ActiveSupport::TestCase
  def resolve(env)
    DevelopmentQueueDatabase.resolve(env)
  end

  test "uses the default queue database on the default connection" do
    assert_equal({ url: nil, database: "nerdbot_development_queue" }, resolve({}))
  end

  test "ignores blank values" do
    env = { "DATABASE_URL" => " ", "QUEUE_DATABASE_URL" => "", "QUEUE_DB_NAME" => "" }

    assert_equal({ url: nil, database: "nerdbot_development_queue" }, resolve(env))
  end

  test "honors QUEUE_DB_NAME on the default connection" do
    assert_equal({ url: nil, database: "my_queue" }, resolve("QUEUE_DB_NAME" => "my_queue"))
  end

  test "QUEUE_DATABASE_URL wins over everything else" do
    env = {
      "QUEUE_DATABASE_URL" => "mysql2://root@db:3306/explicit_queue",
      "DATABASE_URL" => "mysql2://root@127.0.0.1:3306/nerdbot_e2e",
      "QUEUE_DB_NAME" => "my_queue"
    }

    assert_equal "mysql2://root@db:3306/explicit_queue", resolve(env)[:url]
  end

  test "follows DATABASE_URL with a _queue suffix" do
    env = { "DATABASE_URL" => "mysql2://root:secret@127.0.0.1:3306/nerdbot_e2e?pool=5" }

    assert_equal(
      { url: "mysql2://root:secret@127.0.0.1:3306/nerdbot_e2e_queue?pool=5", database: "nerdbot_e2e_queue" },
      resolve(env)
    )
  end

  test "reads the primary database from a database query parameter" do
    env = { "DATABASE_URL" => "mysql2://root@127.0.0.1:3306?database=nerdbot_mine&encoding=utf8mb4" }

    assert_equal(
      { url: "mysql2://root@127.0.0.1:3306/nerdbot_mine_queue?encoding=utf8mb4", database: "nerdbot_mine_queue" },
      resolve(env)
    )
  end

  test "uses the default queue name when DATABASE_URL names no database" do
    env = { "DATABASE_URL" => "mysql2://root@127.0.0.1:3306" }

    assert_equal(
      { url: "mysql2://root@127.0.0.1:3306/nerdbot_development_queue", database: "nerdbot_development_queue" },
      resolve(env)
    )
  end

  test "QUEUE_DB_NAME overrides the derived name but keeps DATABASE_URL's connection" do
    env = { "DATABASE_URL" => "mysql2://root@db.local:3307/nerdbot_e2e", "QUEUE_DB_NAME" => "my_queue" }

    assert_equal({ url: "mysql2://root@db.local:3307/my_queue", database: "my_queue" }, resolve(env))
  end

  test "config/database.yml uses it for the development queue database" do
    resolved = resolve("DATABASE_URL" => "mysql2://root@127.0.0.1:3306?database=nerdbot_mine")
    DevelopmentQueueDatabase.stubs(:resolve).returns(resolved)
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("development"))

    configs = ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration)
    queue = configs.configs_for(env_name: "development", name: "queue")

    assert_equal "nerdbot_mine_queue", queue.database
    assert_equal "127.0.0.1", queue.host
    assert_equal "db/queue_migrate", queue.migrations_paths
  end
end

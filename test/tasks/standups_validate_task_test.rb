require "test_helper"
require "rake"

class StandupsValidateTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("standups:validate")
    @config_dir = Dir.mktmpdir("test_validate_standups")
  end

  teardown do
    FileUtils.rm_rf(@config_dir) if @config_dir && File.exist?(@config_dir)
  end

  def run_validate
    ENV["STANDUPS_CONFIG_DIR"] = @config_dir.to_s
    Rake::Task["standups:validate"].reenable
    capture_io { Rake::Task["standups:validate"].invoke }
    nil
  rescue SystemExit => e
    e
  ensure
    ENV.delete("STANDUPS_CONFIG_DIR")
  end

  def write_yaml(filename, data)
    File.write(File.join(@config_dir, filename), data.to_yaml)
  end

  def write_raw(filename, content)
    File.write(File.join(@config_dir, filename), content)
  end

  def valid_config
    {
      "name" => "Test Standup",
      "slack_channel" => "test-channel",
      "questions" => [ "What did you do?", "Any blockers?" ],
      "schedule" => {
        "days" => %w[monday tuesday wednesday thursday friday],
        "time" => "09:00"
      },
      "participants" => [
        { "slack_id" => "U111", "name" => "Alice", "active" => true }
      ]
    }
  end

  test "passes with valid config" do
    write_yaml("valid.yml", valid_config)
    result = run_validate
    assert_nil result, "Expected no SystemExit for valid config"
  end

  test "fails when name is missing" do
    config = valid_config.except("name")
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails when slack_channel is missing" do
    config = valid_config.except("slack_channel")
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails when questions is missing" do
    config = valid_config.except("questions")
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails when questions is not an array" do
    config = valid_config.merge("questions" => "not an array")
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails with invalid schedule time format" do
    config = valid_config.merge("schedule" => { "time" => "25:00" })
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails with invalid schedule time string" do
    config = valid_config.merge("schedule" => { "time" => "noon" })
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails with invalid day name" do
    config = valid_config.merge("schedule" => { "days" => [ "monday", "notaday" ] })
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails when participant missing slack_id" do
    config = valid_config.merge("participants" => [ { "name" => "Alice" } ])
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails when participant missing name" do
    config = valid_config.merge("participants" => [ { "slack_id" => "U111" } ])
    write_yaml("bad.yml", config)
    result = run_validate
    assert_equal 1, result.status
  end

  test "fails with invalid YAML syntax" do
    write_raw("bad.yml", "name: [unterminated")
    result = run_validate
    assert_equal 1, result.status
  end

  test "reports errors with file name" do
    config = valid_config.except("name")
    write_yaml("broken.yml", config)
    ENV["STANDUPS_CONFIG_DIR"] = @config_dir.to_s
    Rake::Task["standups:validate"].reenable
    output, = capture_io do
      begin
        Rake::Task["standups:validate"].invoke
      rescue SystemExit
      end
    end
    ENV.delete("STANDUPS_CONFIG_DIR")
    assert_match(/broken\.yml/, output)
    assert_match(/Missing required key: 'name'/, output)
  end

  test "validates multiple files and reports all errors" do
    write_yaml("good.yml", valid_config)
    write_yaml("bad.yml", valid_config.except("questions"))
    ENV["STANDUPS_CONFIG_DIR"] = @config_dir.to_s
    Rake::Task["standups:validate"].reenable
    output, = capture_io do
      begin
        Rake::Task["standups:validate"].invoke
      rescue SystemExit
      end
    end
    ENV.delete("STANDUPS_CONFIG_DIR")
    assert_match(/good\.yml/, output)
    assert_match(/bad\.yml/, output)
    assert_match(/1 file\(s\) with errors/, output)
  end
end

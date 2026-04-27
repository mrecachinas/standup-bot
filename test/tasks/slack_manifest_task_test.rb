require "test_helper"
require "rake"

class SlackManifestTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("slack:manifest")
  end

  test "prints manifest YAML for APP_URL" do
    output, = with_manifest_env("APP_URL" => "https://standup.example.com", "SLACK_APP_NAME" => "Team Standup") do
      Rake::Task["slack:manifest"].reenable
      capture_io { Rake::Task["slack:manifest"].invoke }
    end

    manifest = YAML.safe_load(output)
    assert_equal "Team Standup", manifest.dig("display_information", "name")
    assert_equal "https://standup.example.com/slack/events",
      manifest.dig("settings", "event_subscriptions", "request_url")
  end

  test "requires APP_URL" do
    error = with_manifest_env("APP_URL" => nil, "SLACK_APP_URL" => nil) do
      Rake::Task["slack:manifest"].reenable
      assert_raises(SystemExit) do
        capture_io { Rake::Task["slack:manifest"].invoke }
      end
    end

    assert_equal 1, error.status
  end

  private

  def with_manifest_env(values)
    previous = values.transform_values { nil }
    values.each_key { |key| previous[key] = ENV[key] }

    values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

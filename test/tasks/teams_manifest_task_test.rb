require "test_helper"
require "rake"

class TeamsManifestTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("teams:manifest")
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  test "prints manifest JSON" do
    output, = with_env("APP_URL" => "https://standup.example.com", "TEAMS_APP_ID" => "11111111-2222-3333-4444-555555555555") do
      Rake::Task["teams:manifest"].reenable
      capture_io { Rake::Task["teams:manifest"].invoke }
    end

    assert_equal "11111111-2222-3333-4444-555555555555", JSON.parse(output)["id"]
  end

  test "requires APP_URL" do
    error = with_env("APP_URL" => nil, "TEAMS_APP_ID" => "11111111-2222-3333-4444-555555555555") do
      Rake::Task["teams:manifest"].reenable
      assert_raises(SystemExit) { capture_io { Rake::Task["teams:manifest"].invoke } }
    end

    assert_equal 1, error.status
  end
end

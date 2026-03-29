require "test_helper"
require "rake"

class StandupsImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("standups:import")

    @config_dir = Dir.mktmpdir("test_standups")
  end

  teardown do
    FileUtils.rm_rf(@config_dir) if @config_dir && File.exist?(@config_dir)
  end

  def run_import
    ENV["STANDUPS_CONFIG_DIR"] = @config_dir.to_s
    Rake::Task["standups:import"].reenable
    capture_io { Rake::Task["standups:import"].invoke }
  ensure
    ENV.delete("STANDUPS_CONFIG_DIR")
  end

  def write_yaml(filename, data)
    File.write(File.join(@config_dir, filename), data.to_yaml)
  end

  test "creates a new standup from YAML" do
    write_yaml("team.yml", {
      "name" => "Morning Standup",
      "slack_channel" => "eng-standup",
      "intro" => "Good morning!",
      "outro" => "Have a great day!",
      "questions" => [ "What did you do?", "What will you do?" ],
      "schedule" => {
        "timezone" => "America/New_York",
        "days" => %w[monday tuesday wednesday thursday friday],
        "time" => "09:30"
      }
    })

    assert_difference "Standup.count", 1 do
      run_import
    end

    standup = Standup.find_by(name: "Morning Standup")
    assert_equal "eng-standup", standup.slack_channel
    assert_equal "Good morning!", standup.intro
    assert_equal "Have a great day!", standup.outro
    assert_equal [ "What did you do?", "What will you do?" ], standup.questions
    assert_equal "weekdays", standup.schedule_type
    assert_equal 9, standup.default_hour
    assert_equal 30, standup.default_minute
    assert standup.respect_timezone
  end

  test "updates an existing standup" do
    existing = Standup.create!(
      name: "Morning Standup",
      slack_channel: "old-channel",
      questions: [ "Old question?" ]
    )

    write_yaml("team.yml", {
      "name" => "Morning Standup",
      "slack_channel" => "new-channel",
      "questions" => [ "New question?" ],
      "schedule" => { "time" => "10:00" }
    })

    assert_no_difference "Standup.count" do
      run_import
    end

    existing.reload
    assert_equal "new-channel", existing.slack_channel
    assert_equal [ "New question?" ], existing.questions
    assert_equal 10, existing.default_hour
  end

  test "maps weekly schedule with specific days" do
    write_yaml("team.yml", {
      "name" => "Weekly Sync",
      "slack_channel" => "sync",
      "questions" => [ "Updates?" ],
      "schedule" => {
        "days" => %w[monday thursday],
        "time" => "14:00"
      }
    })

    run_import

    standup = Standup.find_by(name: "Weekly Sync")
    assert_equal "weekly", standup.schedule_type
    assert_equal [ 1, 4 ], standup.schedule_days
    assert_equal 14, standup.default_hour
    assert_equal 0, standup.default_minute
  end

  test "maps daily schedule when all seven days specified" do
    write_yaml("team.yml", {
      "name" => "Every Day",
      "slack_channel" => "daily",
      "questions" => [ "Status?" ],
      "schedule" => {
        "days" => %w[monday tuesday wednesday thursday friday saturday sunday],
        "time" => "08:00"
      }
    })

    run_import

    standup = Standup.find_by(name: "Every Day")
    assert_equal "daily", standup.schedule_type
  end

  test "creates participants from YAML" do
    write_yaml("team.yml", {
      "name" => "Team Standup",
      "slack_channel" => "team",
      "questions" => [ "Update?" ],
      "schedule" => { "time" => "09:00" },
      "participants" => [
        { "slack_id" => "U111", "name" => "Alice", "active" => true },
        { "slack_id" => "U222", "name" => "Bob", "active" => false }
      ]
    })

    run_import

    standup = Standup.find_by(name: "Team Standup")
    assert_equal 2, standup.standup_participants.count

    alice = standup.standup_participants.find_by(slack_id: "U111")
    assert_equal "Alice", alice.slack_name
    assert alice.active

    bob = standup.standup_participants.find_by(slack_id: "U222")
    assert_equal "Bob", bob.slack_name
    assert_not bob.active
  end

  test "deactivates participants not in YAML" do
    standup = Standup.create!(
      name: "Team Standup",
      slack_channel: "team",
      questions: [ "Update?" ]
    )
    removed = StandupParticipant.create!(
      standup: standup, slack_id: "UREMOVED", slack_name: "Removed", active: true
    )

    write_yaml("team.yml", {
      "name" => "Team Standup",
      "slack_channel" => "team",
      "questions" => [ "Update?" ],
      "schedule" => { "time" => "09:00" },
      "participants" => [
        { "slack_id" => "UKEPT", "name" => "Kept", "active" => true }
      ]
    })

    run_import

    removed.reload
    assert_not removed.active
  end

  test "processes multiple YAML files" do
    write_yaml("team_a.yml", {
      "name" => "Team A",
      "slack_channel" => "team-a",
      "questions" => [ "Q?" ],
      "schedule" => { "time" => "09:00" }
    })
    write_yaml("team_b.yml", {
      "name" => "Team B",
      "slack_channel" => "team-b",
      "questions" => [ "Q?" ],
      "schedule" => { "time" => "10:00" }
    })

    assert_difference "Standup.count", 2 do
      run_import
    end
  end
end

require "test_helper"

class StandupParticipantImporterTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
  end

  test "imports comma separated participants" do
    importer = StandupParticipantImporter.new(@standup, now: Time.zone.parse("2026-04-27 12:00:00"))

    result = importer.import_text("UIMPORT1,Alice Import,America/New_York,true\nUIMPORT2,Bob Import,UTC,false")

    assert result.success?, result.errors.join(", ")
    assert_equal 2, result.created.size
    assert_equal 2, result.changes.size

    alice = @standup.standup_participants.find_by!(slack_id: "UIMPORT1")
    assert_equal "Alice Import", alice.slack_name
    assert_equal "America/New_York", alice.cached_timezone
    assert_equal Time.zone.parse("2026-04-27 12:00:00"), alice.cached_timezone_updated_at

    bob = @standup.standup_participants.find_by!(slack_id: "UIMPORT2")
    assert_not bob.active
  end

  test "updates existing participants and reports validation errors" do
    participant = standup_participants(:one)
    importer = StandupParticipantImporter.new(@standup)

    result = importer.import_text("#{participant.slack_id},Renamed User,UTC,true\nUBAD,Bad User,Invalid/Zone,true")

    assert_not result.success?
    assert_equal 1, result.updated.size
    assert_equal "Renamed User", participant.reload.slack_name
    assert_includes result.errors.first, "Cached timezone is not a valid timezone"
    assert_nil @standup.standup_participants.find_by(slack_id: "UBAD")
  end

  test "sync profiles can deactivate missing participants" do
    kept = StandupParticipant.create!(standup: @standup, slack_id: "USYNC1", slack_name: "Old Name")
    missing = StandupParticipant.create!(standup: @standup, slack_id: "USYNC2", slack_name: "Missing User")
    importer = StandupParticipantImporter.new(@standup)

    result = importer.sync_profiles(
      [ { "slack_id" => kept.slack_id, "slack_name" => "Synced Name", "cached_timezone" => "America/Chicago" } ],
      deactivate_missing: true
    )

    assert result.success?, result.errors.join(", ")
    assert_equal "Synced Name", kept.reload.slack_name
    assert_equal "America/Chicago", kept.cached_timezone
    assert_not missing.reload.active
    assert result.deactivated.any? { |participant| participant.id == missing.id }
  end
end

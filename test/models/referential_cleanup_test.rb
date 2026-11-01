require "test_helper"

# The app has no database foreign keys, so models own referential cleanup.
class ReferentialCleanupTest < ActiveSupport::TestCase
  test "app schema has no foreign keys" do
    connection = ActiveRecord::Base.connection
    tables = connection.tables.reject { |table| table.start_with?("solid_queue_") }

    foreign_keys = tables.flat_map do |table|
      connection.foreign_keys(table).map { |fk| "#{fk.from_table}.#{fk.column} -> #{fk.to_table}" }
    end

    assert_empty foreign_keys, "Use model `dependent:` options instead of database foreign keys"
  end

  test "deleting a user nullifies the actor on their report generations and audit logs" do
    user = users(:manager)
    generation = report_generations(:failed_daily_report)
    audit_log = AuditLog.create!(actor: user, action: "standup.updated", auditable: standups(:daily))
    identity = user.identities.create!(platform: "slack", platform_user_id: "UCLEANUP")
    ownership_ids = user.standup_ownerships.ids
    assert_equal user, generation.actor
    assert_not_empty ownership_ids

    user.destroy!

    assert_nil generation.reload.actor_id
    assert_nil audit_log.reload.actor_id
    assert_not UserIdentity.exists?(identity.id)
    assert_not StandupOwnership.where(id: ownership_ids).exists?
  end

  test "deleting a standup removes its child rows" do
    standup = standups(:daily)
    standup.update!(schedule_type: "daily", default_hour: 9, default_minute: 0)
    standup.standup_schedule_exceptions.create!(exception_type: "holiday", original_date: Date.new(2026, 4, 27))

    children = {
      StandupParticipant => standup.standup_participants.ids,
      StandupResponse => standup.standup_responses.ids,
      StandupOwnership => standup.standup_ownerships.ids,
      StandupScheduleException => standup.standup_schedule_exceptions.ids,
      ReportConfiguration => [ standup.report_configuration.id ],
      ReportGeneration => standup.report_generations.ids
    }
    children.each { |model, ids| assert_not_empty ids, "expected #{model} fixtures for the daily standup" }

    standup.destroy!

    children.each do |model, ids|
      assert_not model.where(id: ids).exists?, "#{model} rows were left behind"
    end
  end
end

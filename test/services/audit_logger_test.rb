require "test_helper"

class AuditLoggerTest < ActiveSupport::TestCase
  test "creates audit records with actor snapshots" do
    assert_difference "AuditLog.count", 1 do
      AuditLogger.log!(
        actor: users(:manager),
        action: "standup.update",
        auditable: standups(:daily),
        metadata: { "field" => "name" }
      )
    end

    audit_log = AuditLog.last
    assert_equal users(:manager), audit_log.actor
    assert_equal "manager@example.com", audit_log.actor_email
    assert_equal "manager", audit_log.actor_role
    assert_equal "standup.update", audit_log.action
    assert_equal "name", audit_log.metadata["field"]
  end
end

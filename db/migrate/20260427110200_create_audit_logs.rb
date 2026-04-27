class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :actor_email
      t.string :actor_role
      t.string :actor_label
      t.string :action, null: false
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.json :metadata
      t.string :request_id
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    add_index :audit_logs, [ :auditable_type, :auditable_id ]
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end

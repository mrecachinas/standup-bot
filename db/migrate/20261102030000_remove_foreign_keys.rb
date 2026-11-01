# The app doesn't use database foreign keys. Models own referential cleanup
# through `dependent:` options instead. Solid Queue's own FKs are untouched.
class RemoveForeignKeys < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :audit_logs, :users, column: :actor_id
    remove_foreign_key :report_configurations, :standups, column: :standup_id
    remove_foreign_key :report_generations, :report_configurations, column: :report_configuration_id
    remove_foreign_key :report_generations, :standups, column: :standup_id
    remove_foreign_key :report_generations, :users, column: :actor_id
    remove_foreign_key :standup_ownerships, :standups, column: :standup_id
    remove_foreign_key :standup_ownerships, :users, column: :user_id
    remove_foreign_key :standup_participants, :standups, column: :standup_id
    remove_foreign_key :standup_schedule_exceptions, :standups, column: :standup_id
    remove_foreign_key :user_identities, :users, column: :user_id
  end
end

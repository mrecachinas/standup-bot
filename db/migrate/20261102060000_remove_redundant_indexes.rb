# Each of these is the leading column of a composite index on the same table,
# which serves the same lookups.
class RemoveRedundantIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :report_generations, :standup_id, name: "index_report_generations_on_standup_id"
    remove_index :standup_ownerships, :standup_id, name: "index_standup_ownerships_on_standup_id"
    remove_index :standup_ownerships, :user_id, name: "index_standup_ownerships_on_user_id"
    remove_index :standup_participants, :standup_id, name: "index_standup_participants_on_standup_id"
    remove_index :standup_responses, :standup_id, name: "index_standup_responses_on_standup_id"
    remove_index :standup_schedule_exceptions, :standup_id, name: "index_standup_schedule_exceptions_on_standup_id"
  end
end

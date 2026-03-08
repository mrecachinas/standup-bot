class AddIndexAndCachedTimezone < ActiveRecord::Migration[8.0]
  def change
    add_index :standup_responses, [ :slack_id, :status ]
    add_column :standup_participants, :cached_timezone, :string
  end
end

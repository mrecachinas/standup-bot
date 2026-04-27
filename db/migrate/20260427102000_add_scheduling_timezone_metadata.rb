class AddSchedulingTimezoneMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :standup_participants, :cached_timezone_updated_at, :datetime
    add_column :standup_participants, :vacation_until, :date

    add_column :standup_responses, :standup_date, :date
    add_index :standup_responses,
      [ :standup_id, :slack_id, :standup_date ],
      unique: true,
      name: "idx_standup_responses_on_standup_user_date"
  end
end

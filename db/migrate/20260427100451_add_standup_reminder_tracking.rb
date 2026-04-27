class AddStandupReminderTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :standups, :reminder_enabled, :boolean, null: false, default: true
    add_column :standups, :reminder_after_minutes, :integer, null: false, default: 120
    add_column :standups, :max_reminders, :integer, null: false, default: 1

    add_column :standup_responses, :reminder_count, :integer, null: false, default: 0
    add_column :standup_responses, :last_reminder_at, :datetime
  end
end

class CreateStandupScheduleExceptions < ActiveRecord::Migration[8.0]
  def change
    create_table :standup_schedule_exceptions do |t|
      t.references :standup, null: false, foreign_key: true
      t.string :exception_type, null: false
      t.date :original_date, null: false
      t.date :rescheduled_date
      t.integer :rescheduled_hour
      t.integer :rescheduled_minute
      t.string :rescheduled_timezone
      t.text :reason
      t.timestamps
    end

    add_index :standup_schedule_exceptions,
      [ :standup_id, :original_date ],
      unique: true,
      name: "idx_standup_schedule_exceptions_on_standup_date"
    add_index :standup_schedule_exceptions,
      [ :exception_type, :original_date ],
      name: "idx_standup_schedule_exceptions_on_type_date"
  end
end

class CreateReportGenerations < ActiveRecord::Migration[8.0]
  def change
    create_table :report_generations do |t|
      t.references :standup, null: false, foreign_key: true
      t.references :report_configuration, null: true, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "queued"
      t.string :delivery_channel, null: false
      t.json :recipients
      t.string :report_format, null: false
      t.string :detail_level, null: false
      t.date :standup_date, null: false
      t.string :timezone
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.json :metadata
      t.timestamps
    end

    add_index :report_generations, [ :standup_id, :requested_at ]
    add_index :report_generations, [ :status, :requested_at ]
  end
end

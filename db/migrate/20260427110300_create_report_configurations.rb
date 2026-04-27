class CreateReportConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :report_configurations do |t|
      t.references :standup, null: false, foreign_key: true, index: { unique: true }
      t.string :delivery_channel, null: false
      t.json :recipients
      t.string :report_format, null: false, default: "slack"
      t.string :detail_level, null: false, default: "detailed"
      t.timestamps
    end
  end
end

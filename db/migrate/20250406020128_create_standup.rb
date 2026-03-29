class CreateStandup < ActiveRecord::Migration[8.0]
  def change
    create_table :standups do |t|
      t.string :name, null: false
      t.string :slack_channel, null: false
      t.text :intro
      t.text :outro
      t.json :questions

      # Schedule configuration
      t.string :schedule_type, null: false, default: 'daily'
      t.json :schedule_days
      t.integer :default_hour, null: false, default: 9
      t.integer :default_minute, null: false, default: 0
      t.boolean :respect_timezone, null: false, default: true

      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end

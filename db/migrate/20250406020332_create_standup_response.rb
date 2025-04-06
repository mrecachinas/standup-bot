class CreateStandupResponse < ActiveRecord::Migration[8.0]
  def change
    create_table :standup_responses do |t|
      t.string :slack_id, null: false
      t.references :standup, null: false, foreign_key: false
      t.string :status, null: false, default: "pending"
      t.string :slack_channel
      t.json :answers, null: false, default: []
      t.timestamps
    end
  end
end

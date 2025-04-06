class CreateStandupParticipants < ActiveRecord::Migration[8.0]
  def change
    create_table :standup_participants do |t|
      t.references :standup, null: false, foreign_key: true
      t.string :slack_id, null: false
      t.string :slack_name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :standup_participants, [ :standup_id, :slack_id ], unique: true
  end
end

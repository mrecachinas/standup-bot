class CreateStandupOwnerships < ActiveRecord::Migration[8.0]
  def change
    create_table :standup_ownerships do |t|
      t.references :standup, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "manager"
      t.timestamps
    end

    add_index :standup_ownerships, [ :standup_id, :user_id ], unique: true
    add_index :standup_ownerships, [ :user_id, :standup_id ]
  end
end

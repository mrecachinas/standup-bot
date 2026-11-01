class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def up
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :platform, null: false
      t.string :platform_user_id, null: false
      t.timestamps
    end
    add_index :user_identities, [ :platform, :platform_user_id ], unique: true
    add_index :user_identities, [ :user_id, :platform ], unique: true

    execute <<~SQL.squish
      INSERT INTO user_identities (user_id, platform, platform_user_id, created_at, updated_at)
      SELECT id, 'slack', slack_user_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM users
      WHERE slack_user_id IS NOT NULL AND slack_user_id <> ''
    SQL

    remove_index :users, :slack_user_id
    remove_column :users, :slack_user_id
  end

  def down
    add_column :users, :slack_user_id, :string
    add_index :users, :slack_user_id, unique: true

    execute <<~SQL.squish
      UPDATE users
      SET slack_user_id = (
        SELECT platform_user_id FROM user_identities
        WHERE user_identities.user_id = users.id AND user_identities.platform = 'slack'
      )
    SQL

    drop_table :user_identities
  end
end

class AddTeamsSupport < ActiveRecord::Migration[8.1]
  def change
    # A readable channel name for platforms whose channel IDs aren't (Teams).
    add_column :standups, :platform_channel_name, :string

    # Where to reach someone directly. Teams needs a conversation ID and
    # service URL before the bot can DM a person; Slack doesn't use this.
    create_table :chat_conversations do |t|
      t.string :platform, null: false
      t.string :platform_user_id, null: false
      t.string :conversation_id, null: false
      t.string :service_url
      t.string :tenant_id
      t.timestamps
    end
    add_index :chat_conversations, [ :platform, :platform_user_id ], unique: true
  end
end

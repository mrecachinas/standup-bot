class MakeChatColumnsPlatformNeutral < ActiveRecord::Migration[8.1]
  def change
    add_column :standups, :platform, :string, null: false, default: "slack"
    add_index :standups, :platform
    rename_column :standups, :slack_channel, :platform_channel

    rename_column :standup_participants, :slack_id, :platform_user_id
    rename_column :standup_participants, :slack_name, :display_name

    rename_column :standup_responses, :slack_id, :platform_user_id
    rename_column :standup_responses, :slack_channel, :dm_channel
    rename_column :standup_responses, :slack_message_ts, :platform_message_id
  end
end

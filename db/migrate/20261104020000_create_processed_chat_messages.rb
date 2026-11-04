# Records each message people send the bot once it's been handled, so a
# redelivered event (chat platforms resend ones they think weren't received)
# or a message picked up again from DM history isn't handled twice.
class CreateProcessedChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_chat_messages do |t|
      t.string :platform, null: false
      t.string :platform_user_id, null: false
      t.string :message_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :processed_chat_messages, [ :platform, :platform_user_id, :message_id ], unique: true, name: "idx_processed_chat_messages_on_message"
    add_index :processed_chat_messages, :created_at
  end
end

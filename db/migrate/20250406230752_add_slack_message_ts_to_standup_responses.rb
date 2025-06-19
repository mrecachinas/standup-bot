class AddSlackMessageTsToStandupResponses < ActiveRecord::Migration[8.0]
  def change
    add_column :standup_responses, :slack_message_ts, :string
  end
end

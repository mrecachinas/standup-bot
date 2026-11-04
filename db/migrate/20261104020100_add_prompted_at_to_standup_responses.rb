# When the bot's latest prompt in a run (the first question, the next one, or
# the sign-off) reached the person, by the chat platform's clock. A message
# sent before then was typed before that prompt showed up, so it continues
# the previous answer instead of answering a question the person hadn't seen.
class AddPromptedAtToStandupResponses < ActiveRecord::Migration[8.1]
  def change
    add_column :standup_responses, :prompted_at, :datetime, precision: 6
  end
end

class AddAvatarUrlToUsersAndParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :standup_participants, :avatar_url, :string
    add_column :users, :avatar_url, :string
  end
end

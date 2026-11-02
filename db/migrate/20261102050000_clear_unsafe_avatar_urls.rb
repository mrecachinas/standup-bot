# Avatar URLs are now checked when they're assigned (AvatarUrl) instead of every
# time they're shown, so clear any stored value that wouldn't pass that check.
class ClearUnsafeAvatarUrls < ActiveRecord::Migration[8.1]
  def up
    %w[standup_participants users].each do |table|
      execute <<~SQL
        UPDATE #{table} SET avatar_url = NULL
        WHERE avatar_url IS NOT NULL AND (avatar_url NOT LIKE 'https://%' OR LENGTH(avatar_url) > #{AvatarUrl::MAX_LENGTH})
      SQL
    end
  end

  def down
  end
end

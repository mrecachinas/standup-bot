# Bearer tokens on /api are looked up by their digest.
class IndexUsersOnAccessTokenDigest < ActiveRecord::Migration[8.1]
  def change
    add_index :users, :access_token_digest
  end
end

class ChangeUsersDefaultRoleToUser < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :role, from: "manager", to: "user"
  end
end

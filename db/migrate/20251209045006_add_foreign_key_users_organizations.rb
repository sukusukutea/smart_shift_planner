class AddForeignKeyUsersOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :organizations
  end
end

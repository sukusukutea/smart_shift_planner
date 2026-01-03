class AddActiveToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :active, :boolean, null: false, default: true
    add_index :staffs, :active
  end
end

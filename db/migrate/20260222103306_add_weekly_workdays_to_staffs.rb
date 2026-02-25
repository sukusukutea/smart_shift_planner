class AddWeeklyWorkdaysToStaffs < ActiveRecord::Migration[8.0]
  def change
    add_column :staffs, :weekly_workdays, :integer
    add_index  :staffs, :weekly_workdays
  end
end

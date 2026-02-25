class RemoveIndexFromStaffsWeeklyWorkdays < ActiveRecord::Migration[8.0]
  def change
    remove_index :staffs, :weekly_workdays
  end
end

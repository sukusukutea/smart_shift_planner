class AddStaffDayTimeOptionToShiftDayAssignments < ActiveRecord::Migration[8.1]
  def change
    add_reference :shift_day_assignments, :staff_day_time_option, null: true, foreign_key: true
  end
end

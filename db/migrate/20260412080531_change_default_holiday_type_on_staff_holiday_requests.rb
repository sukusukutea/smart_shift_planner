class ChangeDefaultHolidayTypeOnStaffHolidayRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_default :staff_holiday_requests, :holiday_type, from: 1, to: 0
  end
end

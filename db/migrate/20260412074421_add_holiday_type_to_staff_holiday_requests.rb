class AddHolidayTypeToStaffHolidayRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_holiday_requests, :holiday_type, :integer, null: false, default: 1
  end
end

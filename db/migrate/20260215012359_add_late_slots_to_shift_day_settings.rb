class AddLateSlotsToShiftDaySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_day_settings, :late_slots, :integer, null: false, default: 1
  end
end

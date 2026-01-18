class StaffHolidayRequest < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  validates :date, presence: true
  validates :staff_id, uniqueness: { scope: [:shift_month_id, :date] }
end

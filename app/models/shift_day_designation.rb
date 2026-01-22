class ShiftDayDesignation < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }

  validates :date, presence: true
  validates :shift_kind, presence: true
  validates :shift_kind, uniqueness: { scope: [:shift_month_id, :date] }
end
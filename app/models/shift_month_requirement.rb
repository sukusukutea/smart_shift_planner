class ShiftMonthRequirement < ApplicationRecord
  belongs_to :shift_month

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }
  enum :role, { nurse: 0, care: 1, any: 2 }

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :required_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end

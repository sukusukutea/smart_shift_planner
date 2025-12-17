class ShiftDayStyle < ApplicationRecord
  belongs_to :shift_day_setting

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }
end

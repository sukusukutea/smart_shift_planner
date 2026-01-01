class ShiftDayAssignment < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }
  enum :source, { draft: 0, confirmed: 1 }
end

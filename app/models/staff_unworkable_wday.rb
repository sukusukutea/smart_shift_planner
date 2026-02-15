class StaffUnworkableWday < ApplicationRecord
  belongs_to :staff

  validates :wday, inclusion: { in: 0..6 }
  validates :wday, uniqueness: { scope: :staff_id }
end

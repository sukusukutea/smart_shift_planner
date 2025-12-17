class ShiftDaySetting < ApplicationRecord
  belongs_to :shift_month

  has_many :shift_day_styles, dependent: :destroy
end

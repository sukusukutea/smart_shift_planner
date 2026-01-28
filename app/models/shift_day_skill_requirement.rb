class ShiftDaySkillRequirement < ApplicationRecord
  belongs_to :shift_month

  enum :shift_kind, { day: 0 }, prefix: true
  enum :skill, { drive: 0, cook: 1 }, prefix: true

  validates :date, presence: true
  validates :required_number, numericality: { greater_than_or_equal_to: 0 }
end

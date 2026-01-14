class ShiftDayAssignment < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }
  enum :source, { draft: 0, confirmed: 1 }

  validates :slot,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  scope :ordered, -> { order(:date, :shift_kind, :slot, :id) }

  def self.next_slot_for(shift_month_id:, date:, shift_kind:, source:, draft_token: nil) # rel:Relationの略 where(...)の返り値は「ActiveRecord::Relation」というオブジェクトのため
    rel = where(shift_month_id: shift_month_id, date: date, shift_kind: shift_kind, source: source)
    rel = rel.where(draft_token: draft_token) if draft_token.present?
    (rel.maximum(:slot) || -1) + 1
  end
end

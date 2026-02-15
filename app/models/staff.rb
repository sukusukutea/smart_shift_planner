class Staff < ApplicationRecord
  belongs_to :occupation
  belongs_to :user
  has_many :shift_day_assignments, dependent: :restrict_with_exception # 間違ってdestroyしてもRails側で止める
  has_many :staff_workable_wdays, dependent: :destroy
  has_many :shift_day_designations, dependent: :restrict_with_exception
  has_many :staff_unworkable_wdays, dependent: :destroy

  enum :workday_constraint, { free: 0, fixed: 1 }
  enum :assignment_policy, { candidate: 0, required: 1 }

  def ng_wday?(date)
    return false if date.nil?

    wday = ShiftMonth.ui_wday(date)
    staff_unworkable_wdays.where(wday: wday).exists?
  end

  scope :active, -> { where(active: true) }

  validates :last_name,     presence: true
  validates :first_name,    presence: true
  validates :last_name_kana,
            presence: true,
            format: {
              with: /\A[ぁ-んー]+\z/,
              message: "はひらがなで入力してください"
            }

  validates :first_name_kana,
            presence: true,
            format: {
              with: /\A[ぁ-んー]+\z/,
              message: "はひらがなで入力してください"
            }
end

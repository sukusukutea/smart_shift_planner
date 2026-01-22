class Staff < ApplicationRecord
  belongs_to :occupation
  belongs_to :user
  has_many :shift_day_assignments, dependent: :restrict_with_exception # 間違ってdestroyしてもRails側で止める
  has_many :staff_workable_wdays, dependent: :destroy
  has_many :shift_day_designations, dependent: :restrict_with_exception

  enum :workday_constraint, { free: 0, fixed: 1 }

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

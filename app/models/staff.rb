class Staff < ApplicationRecord
  belongs_to :occupation
  belongs_to :user
  has_many :shift_day_assignments, dependent: :restrict_with_exception # 間違ってdestroyしてもRails側で止める

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

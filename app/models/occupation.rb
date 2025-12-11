class Occupation < ApplicationRecord
  has_many :staffs, dependent: :nullify # 職種削除時はstaffのoccupation_idをNULLにする

  validates :name, presence: true, uniqueness: { case_sensitive: false } # case_sensitive: falseは大文字小文字を区別しない意味
end

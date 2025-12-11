class Staff < ApplicationRecord
  belongs_to :occupation
  belongs_to :user

  validates :last_name,     presence: true
  validates :first_name,    presence: true
  validates :last_name_kana,  presence: true
  validates :first_name_kana, presence: true
end

occupations = [
  "管理者",
  "看護師",
  "介護士",
  "ケアマネ",
  "管理栄養士",
  "事務"
]

occupations.each do |name|
  Occupation.find_or_create_by!(name: name)
end

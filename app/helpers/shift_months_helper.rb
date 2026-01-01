module ShiftMonthsHelper
  # 画面の「固定５行」を寄せるためのキーを返す
  # staff がnillのときはnil
  def row_key_for(staff)
    return nil if staff.nil?

    name = staff.occupation&.name.to_s

    return :nurse     if name.include?("看護")
    return :care_mgr  if name.include?("ケアマネ")
    return :care      if name.include?("介護")
    return :cook      if name.include?("管理栄養士")
    return :clerk     if name.include?("事務")

    nil
  end
end

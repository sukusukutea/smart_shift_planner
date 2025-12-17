class ShiftMonth < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  has_many :shift_day_settings, dependent: :destroy
  has_many :shift_day_assignments, dependent: :destroy

  SHIFT_KINDS = %i[day early late night].freeze

  # 日別の勤務ON/OFFを返す（MVP:設定がなければ全部ON）
  def enabled_map_for(date)
    setting = shift_day_settings.includes(:shift_day_styles).find_by(date: date)

    # 設定がなければ全部の勤務をONにする（index_withで各勤務にtrueのハッシュつける）
    return SHIFT_KINDS.index_with(true) if setting.nil?

    # settingがある場合：styleが欠けていても全部ONをベースに上書き
    base = SHIFT_KINDS.index_with(true)
    setting.shift_day_styles.each do |style|   # その日に「設定が存在する勤務だけ」１件ずつ取り出す
      base[style.shift_kind.to_sym] = style.enabled   # style.shift_kindでenumの"day"や"night"などのStringが返る。to_symはSymbolキー（:nightなど）に変換 
    end
    base
  end
end

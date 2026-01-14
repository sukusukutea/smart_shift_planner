class ShiftMonth < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  has_many :shift_day_settings, dependent: :destroy
  has_many :shift_day_assignments, dependent: :destroy
  has_many :staff_holiday_requests, dependent: :destroy
  has_many :shift_month_requirements, dependent: :destroy

  validates :year, presence: true
  validates :month, presence: true
  validates :month, inclusion: { in: 1..12 }

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

  def self.ui_wday(date) # Ruby上では日0 月1..となるため、UI上で月0 火1..となるよう変換する
    (date.wday + 6) % 7
  end

  # この月のrequirementを一度だけDBから取り、参照しやすい形に整形して保持する
  # index[[shift_kind, day_of_week]][role] => required_number
  def requirements_index
    @requirements_index ||= begin
      rows = shift_month_requirements
               .select(:shift_kind, :day_of_week, :role, :required_number)

      index = Hash.new { |h, k| h[k] = {} }

      rows.each do |r|
        key = [r.shift_kind.to_sym, r.day_of_week]
        index[key][r.role.to_sym] = r.required_number
      end

      index
    end
  end

  # { nurse: 2, care: 1 } などのHashを返す
  def required_counts_for(date, shift_kind: :day)
    w = self.class.ui_wday(date)

    roles = requirements_index[[shift_kind.to_sym, w]] || {}
    {
      nurse: roles[:nurse].to_i,
      care:  roles[:care].to_i
    }
  end

  def clear_requirements_cache!
    remove_instance_variable(:@requirements_index) if instance_variable_defined?(:@requirements_index)
  end
end

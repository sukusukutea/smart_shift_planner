class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings, :update_settings, :update_day_settings]

  def new
    @shift_month = current_user.shift_months.new
  end

  def create
    @shift_month = current_user.shift_months.new(shift_month_params)
    @shift_month.organization = current_user.organization

    year_string = shift_month_params[:year]
    month_string = shift_month_params[:month]
  
    if year_string.blank?
      @shift_month.errors.add(:year, "を選択してください")
    end

    if month_string.blank?
      @shift_month.errors.add(:month, "を選択してください")
    end

    if @shift_month.errors.any?
      render :new, status: :unprocessable_entity
      return
    end

    year = year_string.to_i
    month = month_string.to_i

    unless (1..12).include?(month)
      @shift_month.errors.add(:month, "は1~12で選択してください。")
      render :new, status: :unprocessable_entity
      return
    end
  
    existing = current_user.shift_months.find_by(year: year, month: month)
    if existing
      redirect_to settings_shift_month_path(existing), notice: "既に作成済みのため、その月を開きました。"
      return # このreturnは「このcreateアクションの処理をここで終了する」の意味
    end

    @shift_month.year = year
    @shift_month.month = month

    if @shift_month.save
      redirect_to settings_shift_month_path(@shift_month)
    else
      flash.now[:alert] = "作成に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def settings
    @month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
    @month_end = @month_begin.end_of_month
    @calendar_begin = @month_begin.beginning_of_week(:monday)
    @calendar_end = @month_end.end_of_week(:monday)
    @dates = (@calendar_begin..@calendar_end).to_a
    @weeks = @dates.each_slice(7).to_a # １週間毎に区切る

    @occupation_order = [
      { key: :nurse, label: "看護", row_class: "occ-row-nurse" },
      { key: :care_mgr, label: "ケアマネ", row_class: "occ-row-small" },
      { key: :care, label: "介護", row_class: "occ-row-care" },
      { key: :cook, label: "調理", row_class: "occ-row-small" },
      { key: :clerk, label: "事務", row_class: "occ-row-small" },
    ]

    @selected_date = parse_selected_date(params[:date]) || @month_begin #日別調整の「選択日」
    @enabled_map = @shift_month.enabled_map_for(@selected_date)
  
    holidays = HolidayJp.between(@calendar_begin, @calendar_end)
    @holiday_by_date = holidays.index_by(&:date)
  end

  def update_settings
    if @shift_month.update(holiday_days_params)
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday")
    else
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday"), alert: "更新に失敗しました。"
    end
  end

  def update_day_settings
    date = Date.iso8601(day_setting_params[:date]) # フォームからくるday_setting[date]は文字列のため、Date.iso8601で厳密にDateに変換。不正ならArgumentErrorになる。
  
    ActiveRecord::Base.transaction do # トランザクション開始（途中で失敗したら全部ロールバックしてくれる）
      setting = @shift_month.shift_day_settings.find_or_create_by!(date: date) # その日のShiftDaySettingを作るor既存取得（！付きのため、バリデーションで失敗したら例外になる）

      enabled_hash = day_setting_params[:enabled] || {} # enabledの入力を取り出す(念の為、nilの場合も通るようにする)

      # ::はスコープ演算子。[ShiftMonthクラスの中にある定数SHIFT_KINDSを参照する]という意味
      ShiftMonth::SHIFT_KINDS.each do |kind| # paramsに入っていない勤務形態があっても、必ず４件分（day/early/late/night）を保存。
        enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash[kind.to_s]) # kindを文字列に変換して、フォームで入力した勤務の結果を取り出し、castでtrue/falseのBoolean型に整える

        style = setting.shift_day_styles.find_or_initialize_by(shift_kind: kind) # すでにその日のshift_kind=:dayがあれば取得。なければメモリ上で新規作成（まだ未保存）
        style.enabled = enabled #ここでenabledを入れて保存
        style.save!
      end
    end

    redirect_to settings_shift_month_path(@shift_month, date: date, tab: "daily"), notice: "日別調整を保存しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "日付が不正です" # 日付がISO8601じゃない時
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "保存に失敗しました : #{e.record.errors.full_messages.join(", ")}"
  end

  private

  def require_organization!
    return if current_user.organization.present?

    redirect_to dashboard_path, alert: "事業所情報が見つかりません。登録情報を確認してください。"
  end

  def set_shift_month
    @shift_month = current_user.shift_months.find(params[:id]) # 他事業所の月を参照できないようにする
  end

  def shift_month_params
    params.require(:shift_month).permit(:year, :month)
  end

  def holiday_days_params
    params.require(:shift_month).permit(:holiday_days)
  end

  def day_setting_params
    params.require(:day_setting).permit(:date, enabled: ShiftMonth::SHIFT_KINDS) # enabled: ShiftMonth::SHIFT_KINDSでday/early/late/night以外を弾く
  end

  def parse_selected_date(str)
    return nil if str.blank?
    Date.iso8601(str)
  rescue ArgumentError
    nil
  end
end

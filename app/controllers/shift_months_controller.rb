class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings, :update_settings, :update_day_settings,
                                        :generate_draft, :preview, :confirm_draft, :show, :add_staff_holiday, :remove_staff_holiday]
  before_action :build_calendar_vars, only: [:settings, :preview, :show]

  def new
    @shift_month = current_user.shift_months.new
    @recent_shift_months = current_user.shift_months.order(year: :desc, month: :desc).limit(3)
  end

  def show
    assignments = @shift_month.shift_day_assignments.confirmed
                              .where(date: @month_begin..@month_end)
                              .select(:date, :shift_kind, :staff_id)

    @saved = Hash.new { |h, k| h[k] = {} }
    assignments.each do |a|
      @saved[a.date.iso8601][a.shift_kind.to_s] = a.staff_id
    end

    preload_staffs_for
    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: @saved
    ).call
  end

  def create
    @shift_month = current_user.shift_months.new(shift_month_params)
    @shift_month.organization = current_user.organization
    @recent_shift_months = current_user.shift_months.order(year: :desc, month: :desc).limit(3)

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

  def destroy
    shift_month = current_user.shift_months.find(params[:id])
    shift_month.destroy!
    redirect_to new_shift_month_path, notice: "削除しました"
  end

  def settings
    prepare_daily_tab_vars
    prepare_holiday_tab_vars
  end

  def update_settings
    if @shift_month.update(holiday_days_params)
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday")
    else
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday"), alert: "更新に失敗しました。"
    end
  end

  def add_staff_holiday
    staff = current_user.staffs.find(params[:staff_id])
    date = Date.iso8601(params[:date])

    @shift_month.staff_holiday_requests.find_or_create_by!(staff: staff, date: date)

    redirect_to settings_shift_month_path(@shift_month, tab:"holiday", staff_id: staff.id), notice: "休日希望を追加しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: params[:staff_id]), alert: "日付の形式が正しくありません"
  end

  def remove_staff_holiday
    request = @shift_month.staff_holiday_requests.find(params[:request_id])
    staff_id = request.staff_id
    request.destroy!

    redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: staff_id), notice: "休日希望を削除しました"
  end

  def update_day_settings
    date = Date.iso8601(day_setting_params[:date])                  # フォームからくるday_setting[date]は文字列のため、Date.iso8601で厳密にDateに変換。不正ならArgumentErrorになる。
  
    ActiveRecord::Base.transaction do                               # トランザクション開始（途中で失敗したら全部ロールバックしてくれる）
      setting = @shift_month.shift_day_settings.find_or_create_by!(date: date)   # その日のShiftDaySettingを作るor既存取得（！付きのため、バリデーションで失敗したら例外になる）

      enabled_hash = day_setting_params[:enabled] || {}                          # enabledの入力を取り出す(念の為、nilの場合も通るようにする)

      # ::はスコープ演算子。[ShiftMonthクラスの中にある定数SHIFT_KINDSを参照する]という意味
      ShiftMonth::SHIFT_KINDS.each do |kind|                                     # paramsに入っていない勤務形態があっても、必ず４件分（day/early/late/night）を保存。
        enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash[kind.to_s])   # kindを文字列に変換して、フォームで入力した勤務の結果を取り出し、castでtrue/falseのBoolean型に整える

        style = setting.shift_day_styles.find_or_initialize_by(shift_kind: kind) # すでにその日のshift_kind=:dayがあれば取得。なければメモリ上で新規作成（まだ未保存）
        style.enabled = enabled                                                  #ここでenabledを入れて保存
        style.save!
      end
    end

    redirect_to settings_shift_month_path(@shift_month, date: date, tab: "daily"), notice: "日別調整を保存しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "日付が不正です" # 日付がISO8601じゃない時
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "保存に失敗しました : #{e.record.errors.full_messages.join(", ")}"
  end

  def generate_draft
    draft_hash = ShiftDrafts::RandomGenerator.new(shift_month: @shift_month).call
    token = SecureRandom.hex(8)

    ShiftDayAssignment.transaction do
      @shift_month.shift_day_assignments.draft.delete_all

      draft_hash.each do |date_str, kinds_hash|
        date = Date.iso8601(date_str)

        kinds_hash.each do |kind_str, staff_id|
          next if staff_id.blank?

          kind = kind_str.to_sym
          next unless ShiftMonth::SHIFT_KINDS.include?(kind)

          @shift_month.shift_day_assignments.create!(
            date: date,
            shift_kind: kind,
            staff_id: staff_id,
            source: :draft,
            draft_token: token
          )
        end
      end
    end

    session[draft_token_session_key] = token
    redirect_to preview_shift_month_path(@shift_month), notice: "シフト案を作成しました。"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month), alert: "日付形式が不正です。"
  end

  def preview
    token = session[draft_token_session_key]
    scope = @shift_month.shift_day_assignments.draft
    scope = scope.where(draft_token: token) if token.present?

    @draft = {}
    scope.find_each do |a|
      dkey = a.date.iso8601
      @draft[dkey] ||= {}
      @draft[dkey][a.shift_kind.to_s] = a.staff_id
    end

    preload_staffs_for # staffのデータ
    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: @draft
    ).call # stats = statistics(統計・集計)の略
  end

  def confirm_draft
    token = session[draft_token_session_key]

    scope = @shift_month.shift_day_assignments.draft
    scope = scope.where(draft_token: token) if token.present?

    unless scope.exists?
      redirect_to preview_shift_month_path(@shift_month), alert: "シフト案がありません。先に作成してください"
      return
    end

    ShiftDayAssignment.transaction do
      @shift_month.shift_day_assignments.confirmed.delete_all

      scope.update_all(
        source: ShiftDayAssignment.sources[:confirmed],
        draft_token: nil,
        updated_at: Time.current
      )
    end

    session.delete(draft_token_session_key)
    redirect_to settings_shift_month_path(@shift_month), notice: "シフトを保存しました"
  rescue ArgumentError
    redirect_to preview_shift_month_path(@shift_month), alert: "日付形式が不正です"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to preview_shift_month_path(@shift_month), alert: "保存に失敗しました： #{e.record.errors.full_messages.join(", ")}"
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

  def draft_token_session_key
    "shift_draft_token_#{@shift_month.id}"
  end

  # カレンダー用の変数(vars:変数達の略)
  def build_calendar_vars
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

    load_holidays
  end

  def load_holidays
    holidays = HolidayJp.between(@calendar_begin, @calendar_end)
    @holiday_by_date = holidays.index_by(&:date)
  end

  # 表示・集計用に全職員を preload（draft / confirmed 共通）
  def preload_staffs_for # staff_id→Staffをまとめて引く（N+1防止）staff.idをキーにした、ActiveRecordオブジェクトのhashを作っている。
    @staff_by_id = current_user.staffs.includes(:occupation).index_by(&:id)
  end

  def prepare_daily_tab_vars
    @selected_date = parse_selected_date(params[:date]) || @month_begin #日別調整の「選択日」
    @enabled_map = @shift_month.enabled_map_for(@selected_date)
  end

  def prepare_holiday_tab_vars
    @all_staffs = current_user.staffs.order(:last_name_kana, :first_name_kana)

    @selected_staff = 
      if params[:staff_id].present?
        current_user.staffs.find_by(id: params[:staff_id])
      else
        nil
      end

    @selected_staff_holidays =
      if @selected_staff
        @shift_month.staff_holiday_requests.where(staff_id: @selected_staff.id).order(:date)
      else
        StaffHolidayRequest.none
      end

    @holiday_requests_by_date = @shift_month.staff_holiday_requests.includes(:staff).group_by(&:date)
  end
end

class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings, :update_settings, :update_daily,
                                        :generate_draft, :preview, :confirm_draft, :show, :add_staff_holiday,
                                        :remove_staff_holiday, :update_weekday_requirements]
  before_action :build_calendar_vars, only: [:settings, :preview, :show]

  def new
    @shift_month = current_user.shift_months.new
    @recent_shift_months = current_user.shift_months.order(year: :desc, month: :desc).limit(3)
  end

  def show
    assignments = @shift_month.shift_day_assignments.confirmed
                              .where(date: @month_begin..@month_end)
                              .select(:date, :shift_kind, :staff_id, :slot)

    @saved = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
    assignments.each do |a|
      dkey = a.date.iso8601
      kind = a.shift_kind.to_s
      @saved[dkey][kind] << { "slot" => a.slot, "staff_id" => a.staff_id }
    end

    @saved.each_value do |kinds_hash|
      kinds_hash.each_value do |rows|
        rows.sort_by! { |r| r["slot"].to_i }
      end
    end

    preload_staffs_for
    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: @saved
    ).call

    alert_dates = (@month_begin..@month_end).to_a

    @alerts_by_date = ShiftDrafts::AlertsBuilder.new(
      dates: alert_dates,
      draft: @saved,
      staff_by_id: @staff_by_id,
      required_by_date: @required_by_date,
      enabled_by_date: {
        day: @day_enabled_by_date,
        early: @early_enabled_by_date,
        late: @late_enabled_by_date,
        night: @night_enabled_by_date
      }
    ).call

    @occupation_order_with_alert = @occupation_order + [
      { key: :alert, label: "アラート", row_class: "occ-row-alert" }
    ]
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
      @shift_month.copy_weekday_requirements_from_base!(user: current_user)
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
    @weekday_requirements = build_weekday_requirements_hash
    @day_req = @shift_month.required_counts_for(@selected_date, shift_kind: :day)
  end

  def update_settings
    if @shift_month.update(holiday_days_params)
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday")
    else
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday"), alert: "更新に失敗しました。"
    end
  end

  def update_daily
    date = Date.iso8601(params.require(:date))          # フォームからくる[date]は文字列のため、Date.iso8601で厳密にDateに変換。不正ならArgumentErrorになる。
    enabled_hash = params.dig(:day_setting, :enabled) || {}
    roles = params.dig(:day_requirements, :roles) || {}

    ActiveRecord::Base.transaction do
      setting = @shift_month.shift_day_settings.find_or_create_by!(date: date)

      ShiftMonth::SHIFT_KINDS.each do |kind|
        enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash[kind.to_s])
        style = setting.shift_day_styles.find_or_initialize_by(shift_kind: kind)
        style.enabled = enabled
        style.save!
      end

      day_enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash["day"])

      if day_enabled
        %w[nurse care].each do |role|
          num = roles[role].to_i
          rec = @shift_month.shift_day_requirements.find_or_initialize_by(
            date: date,
            shift_kind: :day,
            role: role
          )
          rec.required_number = num
          rec.save!
        end
      else
        @shift_month.shift_day_requirements.where(date: date, shift_kind: :day).delete_all
      end
    end

    # requirements_index を使ってるなら念の為クリア（必要なら）
    @shift_month.clear_day_requirements_cache! if @shift_month.respond_to?(:clear_day_requirements_cache!)

    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: date.iso8601), notice: "保存しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "日付が不正です"
  rescue ActionController::ParameterMissing
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: params[:date]), alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
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

  def update_weekday_requirements
    data = params.require(:weekday_requirements)

    ShiftMonthRequirement.transaction do
      data.each do |dow_str, roles_hash| # dow:day_of_weekの略, str:string
        dow = dow_str.to_i

        %w[nurse care].each do |role|
          num = roles_hash[role].to_i

          rec = @shift_month.shift_month_requirements.find_or_initialize_by(
            shift_kind: :day,
            day_of_week: dow,
            role: role
          )
          rec.required_number = num
          rec.save!
        end
      end
    end

    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), notice: "曜日別の必要人数を保存しました"
  rescue ApplicationController::ParameterMissing
    redirect_to setting_shift_month_path(@shift_month, tab: "daily"), alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvaild => each
    redirect_to setting_shift_month_path(@shift_month, tab: "daily"), alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
  end

  def generate_draft
    draft_hash = ShiftDrafts::RandomGenerator.new(shift_month: @shift_month).call
    token = SecureRandom.hex(8)

    ShiftDayAssignment.transaction do
      @shift_month.shift_day_assignments.draft.delete_all

      draft_hash.each do |date_str, kinds_hash|
        date = Date.iso8601(date_str)

        kinds_hash.each do |kind_sym_or_str, rows|
          kind = kind_sym_or_str.to_sym
          next unless ShiftMonth::SHIFT_KINDS.include?(kind)
          
          Array(rows).each do |row|
            staff_id = row[:staff_id] || row["staff_id"]
            slot = row[:slot] || row["slot"]
            next if staff_id.blank?

            @shift_month.shift_day_assignments.create!(
              date: date,
              shift_kind: kind,
              staff_id: staff_id,
              slot: slot.to_i,
              source: :draft,
              draft_token: token
            )
          end
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

    @draft = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
    scope.ordered.find_each do |a|
      dkey = a.date.iso8601
      @draft[dkey][a.shift_kind.to_s] << { "slot" => a.slot, "staff_id" => a.staff_id }
    end

    preload_staffs_for # staffのデータ

    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: @draft
    ).call # stats = statistics(統計・集計)の略

    alert_dates = (@month_begin..@month_end).to_a

    @alerts_by_date = ShiftDrafts::AlertsBuilder.new(
      dates: alert_dates,
      draft: @draft,
      staff_by_id: @staff_by_id,
      required_by_date: @required_by_date,
      enabled_by_date: {
        day: @day_enabled_by_date,
        early: @early_enabled_by_date,
        late: @late_enabled_by_date,
        night: @night_enabled_by_date
      }
    ).call

    @occupation_order_with_alert = @occupation_order + [
      { key: :alert, label: "アラート", row_class: "occ-row-alert" }
    ]
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
      { key: :req, label: "人員設定", row_class: "occ-row-req" },
    ]

    enabled_maps = @shift_month.enabled_map_for_range(@dates)
    @day_enabled_by_date   = enabled_maps[:day]
    @early_enabled_by_date = enabled_maps[:early]
    @late_enabled_by_date  = enabled_maps[:late]
    @night_enabled_by_date = enabled_maps[:night]

    @day_effective_by_date = {}

    @dates.each do |date|
      day_on = @day_enabled_by_date[date]

      req = @shift_month.required_counts_for(date, shift_kind: :day)
      has_staff = req[:nurse].to_i > 0 || req[:care].to_i > 0

      @day_effective_by_date[date] = day_on && has_staff
    end

    @required_by_date = {}
    @dates.each do |date|
      @required_by_date[date] = @shift_month.required_counts_for(date, shift_kind: :day)
    end

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

  def build_weekday_requirements_hash
    hash = (0..6).index_with { { "nurse" => 0, "care" => 0 } } # ここで{ 0 => { "nurse" => 0, "care" => 0 }, ..}をつくる

    @shift_month.shift_month_requirements.day.each do |r| # dayはshift_kind: :day　なので使える
      hash[r.day_of_week][r.role] = r.required_number # hash[曜日][役割] = 必要人数　という構成　例）hash[0]["nurse"] = 2
    end

    hash
  end
end

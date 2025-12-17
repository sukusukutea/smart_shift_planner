class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings]

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
end

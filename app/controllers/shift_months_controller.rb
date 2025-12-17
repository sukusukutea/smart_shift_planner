class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings]

  def new
    @shift_month = current_user.shift_months.new
  end

  def create
    year = shift_month_params[:year].to_i
    month = shift_month_params[:month].to_i
  
    existing = current_user.shift_months.find_by(year: year, month: month)
    if existing
      redirect_to settings_shift_month_path(existing), notice: "既に作成済みのため、その月を開きました。"
      return # このreturnは「このcreateアクションの処理をここで終了する」の意味
    end

    @shift_month = current_user.shift_months.new(shift_month_params)
    @shift_month.organization = current_user.organization

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
    @calendar_begin = @month_begin.beginning_of_week(:sunday)
    @calendar_end = @month_end.end_of_week(:sunday)
    @dates = (@calendar_begin..@calendar_end).to_a
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

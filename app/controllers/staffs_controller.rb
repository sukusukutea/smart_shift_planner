class StaffsController < ApplicationController
  before_action :authenticate_user!

  def index
    @staffs = current_user.staffs.includes(:occupation).order(:last_name_kana, :first_name_kana) # orderはカナ順の表示
  end

  def new
    @staff = current_user.staffs.build # 入力フォームの受け皿作成
    @occupations = Occupation.all
  end

  def create
    @staff = current_user.staffs.build(staff_params) # フォームから送られてきた情報を@staffに入れる
    @occupations = Occupation.all

    if @staff.save
      redirect_to staffs_path, notice: "職員を登録しました。"
    else
      flash.now[:alert] = "登録に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  private

  def staff_params
    params.require(:staff).permit(
      :occupation_id,
      :last_name, :first_name,
      :last_name_kana, :first_name_kana,
      :can_day, :can_early, :can_late, :can_night,
      :can_visit, :can_drive, :can_cook
    )
  end
end

class StaffsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_staff, only: [:edit, :update, :destroy]
  before_action :set_occupations, only: [:new, :create, :edit, :update]

  def index
    @staffs = current_user.staffs.includes(:occupation).order(:last_name_kana, :first_name_kana) # orderはカナ順の表示
    @used_staff_ids = 
      ShiftDayAssignment.where(staff_id: @staffs.select(:id))
                        .distinct
                        .pluck(:staff_id)
                        .to_set
  end

  def new
    @staff = current_user.staffs.build # 入力フォームの受け皿作成
  end

  def create
    @staff = current_user.staffs.build(staff_params) # フォームから送られてきた情報を@staffに入れる

    if @staff.save
      redirect_to staffs_path, notice: "職員を登録しました。"
    else
      flash.now[:alert] = "登録に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @staff.update(staff_params)
      redirect_to staffs_path, notice: "職員情報を更新しました"
    else
      flash.now[:alert] = "更新に失敗しました。入力内容を確認してください。"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @staff.shift_day_assignments.exists?
      @staff.update!(active: false)
      redirect_to staffs_path, notice: "過去のシフトに使用されているため、退職（無効化）にしました"
    else
      @staff.destroy!
      redirect_to staffs_path, notice: "職員を削除しました"
    end
  end

  private

  def set_staff
    @staff = current_user.staffs.find(params[:id])
  end

  def set_occupations
    @occupations = Occupation.all
  end

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

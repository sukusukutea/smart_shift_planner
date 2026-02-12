class StaffsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_staff, only: [:edit, :update, :destroy, :restore]
  before_action :set_occupations, only: [:new, :create, :edit, :update]

  def index
    @staffs = current_user.staffs.includes(:occupation, :staff_workable_wdays).order(:last_name_kana, :first_name_kana) # orderはカナ順の表示
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
      save_workable_wdays!(@staff)
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
      save_workable_wdays!(@staff)
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

  def restore
    @staff.update!(active: true)

    redirect_to staffs_path, notice: "職員を復職しました"
  end

  private

  def set_staff
    @staff = current_user.staffs.includes(:staff_workable_wdays).find(params[:id])
  end

  def set_occupations
    order = ["管理者","介護士","看護師","ケアマネ","管理栄養士","事務"]
    @occupations =
      Occupation.order(
        Arel.sql(
          "CASE occupations.name " +
            order.each_with_index.map { |name, i| "WHEN '#{name}' THEN #{i}" }.join(" ") +
            " ELSE 999 END"
        )
      )
  end

  def staff_params
    params.require(:staff).permit(
      :occupation_id,
      :last_name, :first_name,
      :last_name_kana, :first_name_kana,
      :can_day, :can_early, :can_late, :can_night,
      :can_visit, :can_drive, :can_cook,
      :workday_constraint,
    )
  end

  def save_workable_wdays!(staff)
    wdays = Array(params.dig(:staff, :workable_wdays)).map(&:to_i).uniq
    if staff.workday_constraint == "fixed"
      staff.staff_workable_wdays.delete_all
      wdays.each do |wday|
        staff.staff_workable_wdays.create!(wday: wday)
      end
    else
      staff.staff_workable_wdays.delete_all
    end
  end
end

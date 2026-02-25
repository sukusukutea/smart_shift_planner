class StaffsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_staff, only: [:edit, :update, :destroy, :restore]
  before_action :set_occupations, only: [:new, :create, :edit, :update]

  def index
    @staffs = current_user.staffs.includes(:occupation, :staff_workable_wdays, :staff_unworkable_wdays).order(:last_name_kana, :first_name_kana) # orderはカナ順の表示
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
    @staff = current_user.staffs.build(staff_params)

    ActiveRecord::Base.transaction do
      normalize_weekly_workdays!(@staff)

      if @staff.save
        save_wdays!(@staff)
        redirect_to staffs_path, notice: "職員を登録しました。"
      else
        raise ActiveRecord::Rollback
      end
    end

    unless @staff.persisted?
      flash.now[:alert] = "登録に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @staff.assign_attributes(staff_params)

    success = false
    ActiveRecord::Base.transaction do
      normalize_weekly_workdays!(@staff)

      if @staff.save
        save_wdays!(@staff)
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success
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
    @staff = current_user.staffs.includes(:staff_workable_wdays, :staff_unworkable_wdays).find(params[:id])
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
      :assignment_policy,
      :weekly_workdays
    )
  end

  def normalize_weekly_workdays!(staff)
  staff.weekly_workdays = nil unless staff.workday_constraint == "weekly"
  end

  def save_wdays!(staff)
    workable   = Array(params.dig(:staff, :workable_wdays)).map(&:to_i).uniq
    unworkable = Array(params.dig(:staff, :unworkable_wdays)).map(&:to_i).uniq

    case staff.workday_constraint
    when "fixed"
      staff.staff_unworkable_wdays.delete_all
      staff.staff_workable_wdays.delete_all
      workable.each { |wday| staff.staff_workable_wdays.create!(wday: wday) }

    when "weekly"
      staff.staff_workable_wdays.delete_all
      staff.staff_unworkable_wdays.delete_all
      unworkable.each { |wday| staff.staff_unworkable_wdays.create!(wday: wday) }

    else # "free"
      staff.staff_workable_wdays.delete_all
      staff.staff_unworkable_wdays.delete_all
      unworkable.each { |wday| staff.staff_unworkable_wdays.create!(wday: wday) }
    end
  end
end

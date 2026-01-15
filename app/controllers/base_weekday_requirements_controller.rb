class BaseWeekdayRequirementsController < ApplicationController
  before_action :authenticate_user!

  def show
    @rows = build_table
  end

  def edit
    @rows = build_table
  end

  def update
    data = params.require(:weekday_requirements)
  
    BaseWeekdayRequirement.transaction do
      data.each do |dow_str, roles_hash| # dow = day_of_weekの略
        dow = dow_str.to_i

        %w[nurse care].each do |role|
          num = roles_hash[role].to_i

          rec = current_user.base_weekday_requirements.find_or_initialize_by(
            shift_kind: :day,
            day_of_week: dow,
            role: role
          )

          rec.required_number = num
          rec.save!
        end
      end
    end

    redirect_to base_weekday_requirements_path, notice: "保存しました"
  rescue ApplicationController::ParameterMissing
    redirect_to edit_base_weekday_requirements_path, alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_base_weekday_requirements_path, alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
  end

  private

  def build_table
    hash = (0..6).index_with { { "nurse" => 0, "care" => 0 } }

    current_user.base_weekday_requirements.day.each do |r|
      hash[r.day_of_week][r.role] = r.required_number
    end

    hash
  end
end

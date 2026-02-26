class StaffDayTimeOption < ApplicationRecord
  belongs_to :staff

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position) }

  validates :time_text,
            presence: true,
            if: :needs_time_text?

  validates :time_text,
            format: {
              with: /\A[0-9\-:\/ ]+\z/,
              message: "は半角数字と「- : /（スペース可）」のみで入力してください"
            },
            if: :needs_time_text?

  validate :default_must_be_active
  validate :only_one_active_default_per_staff

  private

  # default にするなら active も true を必須にする（事故防止）
  def default_must_be_active
    return unless is_default?

    if active == false
      errors.add(:is_default, "を有効(active)でない項目に設定できません")
    end
  end

  # 「active な option の中で default は1つだけ」
  def only_one_active_default_per_staff
    return unless staff_id.present?
    return unless is_default?
    return unless active?

    exists_other_default =
      StaffDayTimeOption.where(staff_id: staff_id, active: true, is_default: true)
                        .where.not(id: id)
                        .exists?

    if exists_other_default
      errors.add(:is_default, "は同一職員の有効(active)な項目で1つだけ設定できます")
    end
  end

  def needs_time_text?
  active? || is_default?
  end
end
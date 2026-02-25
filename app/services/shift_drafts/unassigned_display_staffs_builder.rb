module ShiftDrafts
  class UnassignedDisplayStaffsBuilder
    def initialize(dates:, staff_by_id:, assignments_hash:)
      @dates = dates
      @staff_by_id = staff_by_id
      @assignments_hash = assignments_hash
    end

    def call
      display_staffs = @staff_by_id.values.select { |staff| show_holiday_label_staff?(staff) }
      display_ids = display_staffs.map(&:id)

      @dates.index_with do |date|
        day_key = date.iso8601
        kinds_hash = @assignments_hash[day_key] || {}

        assigned_ids =
          kinds_hash.values.flat_map { |rows|
            Array(rows).map { |r| r["staff_id"] || r[:staff_id] }
          }.compact.map(&:to_i).uniq

        unassigned_ids = display_ids - assigned_ids
        unassigned_ids
          .map { |sid| @staff_by_id[sid] }
          .compact
          .select { |staff| show_unassigned_label_on_date?(staff, date) }
      end
    end

    private

    def show_holiday_label_staff?(staff)
      return false if staff.nil?

      occ_name = staff.occupation&.name.to_s

      return true if occ_name.include?("介護")
      return true if occ_name.include?("事務")
      return true if occ_name.include?("管理栄養士")
      return true if occ_name.include?("ケアマネ")

      if occ_name.include?("看護")
        return true
      end

      false
    end

    def show_unassigned_label_on_date?(staff, date)
      return false if staff.nil?

      occ_name = staff.occupation&.name.to_s

      return true if occ_name.include?("介護")
      return true if occ_name.include?("事務")
      return true if occ_name.include?("管理栄養士")
      return true if occ_name.include?("ケアマネ")

      if occ_name.include?("看護")
        constraint = staff.workday_constraint.to_s
        return true if constraint == "free" || constraint == "weekly"

        if constraint == "fixed"
          wday = ShiftMonth.ui_wday(date)
          workable_wdays = staff.staff_workable_wdays.map(&:wday)
          return workable_wdays.include?(wday)
        end

        return false
      end

      false
    end
  end
end

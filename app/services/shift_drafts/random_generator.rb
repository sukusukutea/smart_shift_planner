module ShiftDrafts
  class RandomGenerator
    def initialize(shift_month:)
      @shift_month = shift_month
      @active_scope = @shift_month.user.staffs.where(active: true)
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month

      designations = @shift_month.shift_day_designations.where(date: month_begin..month_end)
      designations_by_date = Hash.new { |h, k| h[k] = {} }
      designations.each do |d|
        designations_by_date[d.date][d.shift_kind.to_s] = d.staff_id
      end # 返り値 designations_by_date[date]["day"] => staff_id　みたいに引ける形

      holiday_ids_by_date =
        @shift_month.staff_holiday_requests
                    .where(date: month_begin..month_end)
                    .group_by(&:date)
                    .transform_values { |rows| rows.map(&:staff_id) }

      draft = {}

      occ_name_by_staff_id = @active_scope
                             .joins(:occupation)
                             .pluck(:id, "occupations.name")
                             .to_h
 
      (month_begin..month_end).each do |date|
        enabled_map = @shift_month.enabled_map_for(date) # その日の勤務のON/OFFを取得 返り値例{ day: true, early: true, late: false, night: true }
        skill_counts = @shift_month.required_skill_counts_for(date)
        
        scope = @active_scope

        holiday_ids = holiday_ids_by_date[date] || []
        assigned_today = Set.new  # SetはRuby標準ライブラリのSetクラス「同じ値を二度入れられない」。同じidが重複できない
        day_hash = {} # その日の最終結果

        ShiftMonth::SHIFT_KINDS.each do |kind|
          sid = designations_by_date.dig(date, kind.to_s)
          next if sid.blank?

          sid = sid.to_i
          (day_hash[kind] ||= []) << { slot: (day_hash[kind]&.size || 0), staff_id: sid }
          assigned_today.add(sid)
        end

        ShiftMonth::SHIFT_KINDS.each do |kind|
          next unless enabled_map[kind] # OFFなら割当しない
          next if kind != :day && day_hash[kind].present?

          if kind == :day
            counts = @shift_month.required_counts_for(date, shift_kind: :day)
            skill_counts = @shift_month.required_skill_counts_for(date)

            fixed_staffs = scope
              .where(can_day: true)
              .where(workday_constraint: :fixed)
              .left_joins(:staff_workable_wdays)
              .where(staff_workable_wdays: { wday: ShiftMonth.ui_wday(date) })
              .where.not(id: holiday_ids)
              .where.not(id: assigned_today.to_a)
              .includes(:occupation)

            day_rows = Array(day_hash[:day])
            slot = day_rows.size
            day_staff_ids = day_rows.map { | row| row[:staff_id] }.compact.map(&:to_i)

            already_nurse = 0
            already_care  = 0

            if day_staff_ids.any?
              already_nurse = day_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("看護") }
              already_care  = day_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("介護") }
            end

            fixed_staffs.each do |staff|
              occ_name = staff.occupation.name

              if occ_name.include?("事務") || occ_name.include?("管理栄養士")
                day_rows << { slot: slot, staff_id: staff.id }
                assigned_today.add(staff.id)
                slot += 1
                next
              end
              
              role =
                if occ_name.include?("看護")
                  :nurse
                elsif occ_name.include?("介護")
                  :care
                else
                  next
                end

              day_rows << { slot: slot, staff_id: staff.id }
              assigned_today.add(staff.id)
              slot += 1
            end

            slot = fill_day_skills!(
              day_rows: day_rows,
              date: date,
              skill_counts: skill_counts,
              assigned_today: assigned_today,
              holiday_ids: holiday_ids,
              scope: scope,
              slot: slot
            )

            fixed_by_id = fixed_staffs.index_by(&:id)
            fixed_nurse = 0
            fixed_care  = 0

            day_rows.each do |row|
              sid = row[:staff_id].to_i
              next unless fixed_by_id.key?(sid)

              staff = fixed_by_id[sid]
              next if staff.nil?

              occ_name = staff.occupation.name
              fixed_nurse += 1 if occ_name.include?("看護")
              fixed_care  += 1 if occ_name.include?("介護")
            end

            need_nurse = [counts[:nurse] - fixed_nurse - already_nurse, 0].max
            need_care  = [counts[:care]  - fixed_care - already_care,  0].max

            slot = fill_day_roles!(
              day_rows: day_rows,
              date: date,
              need_nurse: need_nurse,
              need_care: need_care,
              assigned_today: assigned_today,
              holiday_ids: holiday_ids,
              slot: slot
            )

            day_hash[:day] = day_rows
            next
          end

          staff = pick_staff_for(kind, exclude_ids: assigned_today.to_a + holiday_ids)    # 返り値：今日すでに使ったIDがいればStaffオブジェクト、いなければnil
          next if staff.nil? # 候補0なら空欄

          (day_hash[kind] ||= []) << { slot: 0, staff_id: staff.id }
          assigned_today.add(staff.id)
        end

        draft[date.iso8601] = day_hash # １日のドラフトを格納
      end

      draft
    end
    
    private

    def apply_workday_constraint(scope, date:)
      wday = ShiftMonth.ui_wday(date)
      scope.left_joins(:staff_workable_wdays)
           .where(
             "(staffs.workday_constraint = :free)
              OR
              (staffs.workday_constraint = :fixed
                AND staff_workable_wdays.wday = :wday)",
             wday: wday,
             free: Staff.workday_constraints[:free],
             fixed: Staff.workday_constraints[:fixed]
           )
    end

    def pick_staff_for(kind, exclude_ids:, role: nil, date: nil, skill: nil) # ここでのexclude_ids：すでに選ばれた職員のID配列（同じ人を重複させないため）
      scope = @active_scope

      scope =                          # case kindで条件を足している。kindに応じて対応できる職員だけに絞る
        case kind
        when :day    then scope.where(can_day: true)
        when :early  then scope.where(can_early: true)
        when :late   then scope.where(can_late: true)
        when :night  then scope.where(can_night: true)
        else
          scope.none # 想定外のkindが来たら誰も返さない
        end

      if kind == :day && skill.present?
        case skill.to_sym
        when :drive
          scope = scope.where(can_drive: true)
        when :cook
          scope = scope.where(can_cook: true)
        else
          scope = scope.none
        end
      end

      if kind == :day && role.present?
        scope = scope.joins(:occupation)
        case role
        when :nurse
          scope = scope.where("occupations.name LIKE ?", "%看護%")
        when :care
          scope = scope.where("occupations.name LIKE ?", "%介護%")
        end
      end

      if kind == :day && date.present?
        scope = apply_workday_constraint(scope, date: date)
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?  # any?で配列に一つでも要素があればture. exclude_idsは含めない
      # ここまでで、kindがtrue かつ すでに使用したIDではない、の条件で満たされたscopeができる。

      scope.order(Arel.sql("RANDOM()")).first # Rails7以降、Arel.sqlとは生SQL文字列をそのまま渡すと警告が出るため、意図したSQLと明示
    end

    # 日勤スキルを未選定から追加で埋める。候補をDBから一括取得してshuffleし、Ruby側でpopしていく
    def fill_day_skills!(day_rows:, date:, skill_counts:, assigned_today:, holiday_ids:, scope:, slot:)
      day_staff_ids = day_rows.map { |row| row[:staff_id] }.compact.map(&:to_i)

      drive_have = 0
      cook_have  = 0
      if day_staff_ids.any?
        drive_have = scope.where(id: day_staff_ids, can_drive: true).count
        cook_have  = scope.where(id: day_staff_ids, can_cook:  true).count
      end

      need_drive = [skill_counts[:drive].to_i - drive_have, 0].max
      need_cook  = [skill_counts[:cook].to_i  - cook_have,  0].max

      base_exclude = assigned_today.to_a + holiday_ids

      drive_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :drive)
      while need_drive > 0 && drive_ids.any?
        sid = drive_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        slot += 1
        need_drive -= 1
      end

      base_exclude = assigned_today.to_a + holiday_ids

      cook_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :cook)
      while need_cook > 0 && cook_ids.any?
        sid = cook_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        slot += 1
        need_cook -= 1
      end

      slot
    end

    # 日勤スキル候補のstaff.idを一括取得してシャッフルして返す。返り値：[staff_id, staff_id, ...]
    def day_skill_candidate_ids(date:, exclude_ids:, skill:)
      scope = @active_scope.where(can_day: true)
      scope = apply_workday_constraint(scope, date: date)

      case skill.to_sym
      when :drive
        scope = scope.where(can_drive: true)
      when :cook
        scope = scope.where(can_cook: true)
      else
        return []
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
      scope.pluck(:id).shuffle
    end

    def fill_day_roles!(day_rows:, date:, need_nurse:, need_care:, assigned_today:, holiday_ids:, slot:)
      base_exclude = assigned_today.to_a + holiday_ids

      nurse_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :nurse)
      while need_nurse > 0 && nurse_ids.any?
        sid = nurse_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        slot += 1
        need_nurse -= 1
      end
      
      base_exclude = assigned_today.to_a + holiday_ids

      care_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :care)
      while need_care > 0 && care_ids.any?
        sid = care_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        slot += 1
        need_care -= 1
      end

      slot
    end

    def day_role_candidate_ids(date:, exclude_ids:, role:)
      scope = @active_scope.where(can_day: true)
      scope = apply_workday_constraint(scope, date: date)

      # 職種で絞る
      scope = scope.joins(:occupation)
      case role
      when :nurse
        scope = scope.where("occupations.name LIKE ?", "%看護%")
      when :care
        scope = scope.where("occupations.name LIKE ?", "%介護%")
      else
        return []
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
      scope.pluck(:id).shuffle
    end
  end
end

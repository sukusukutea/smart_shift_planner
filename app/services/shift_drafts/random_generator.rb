module ShiftDrafts
  class RandomGenerator
    def initialize(shift_month:)
      @shift_month = shift_month
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month

      designations = @shift_month.shift_day_designations.where(date: month_begin..month_end)
      designations_by_date = Hash.new { |h, k| h[k] = {} }
      designations.each do |d|
        designations_by_date[d.date][d.shift_kind.to_s] = d.staff_id
      end # 返り値 designations_by_date[date]["day"] => staff_id　みたいに引ける形

      draft = {}

      (month_begin..month_end).each do |date|
        enabled_map = @shift_month.enabled_map_for(date) # その日の勤務のON/OFFを取得 返り値例{ day: true, early: true, late: false, night: true }
        scope = @shift_month.user.staffs.where(active: true)

        holiday_ids = @shift_month.staff_holiday_requests.where(date: date).pluck(:staff_id)
        assigned_today = Set.new  # SetはRuby標準ライブラリのSetクラス「同じ値を二度入れられない」。同じidが重複できない
        day_hash = {} # その日の最終結果

        ShiftMonth::SHIFT_KINDS.each do |kind|
          sid = designations_by_date.dig(date, kind.to_s)
          if sid.present?
            sid = sid.to_i
            (day_hash[kind] ||= []) << { slot: (day_hash[kind]&.size || 0), staff_id: sid }
            assigned_today.add(sid)
            next unless kind == :day
          end

          next unless enabled_map[kind] # OFFなら割当しない

          if kind == :day
            counts = @shift_month.required_counts_for(date, shift_kind: :day)

            wday = ShiftMonth.ui_wday(date)

            fixed_staffs = scope
              .where(workday_constraint: :fixed)
              .where(can_day: true)
              .includes(:staff_workable_wdays, :occupation)
              .select { |s|
                s.staff_workable_wdays.any? { |wd| wd.wday == wday }
              }
              .reject { |s| holiday_ids.include?(s.id) }

            day_rows = Array(day_hash[:day])
            slot = day_rows.size
            already_ids = day_rows.map { |row| row[:staff_id] }.compact.map(&:to_i)

            already_nurse = 0
            already_care  = 0

            if already_ids.any?
              already_nurse = scope.joins(:occupation)
                                  .where(id: already_ids)
                                  .where("occupations.name LIKE ?", "%看護%")
                                  .count

              already_care  = scope.joins(:occupation)
                                  .where(id: already_ids)
                                  .where("occupations.name LIKE ?", "%介護%")
                                  .count
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

            fixed_nurse = fixed_staffs.count { |s| s.occupation.name.include?("看護") }
            fixed_care  = fixed_staffs.count { |s| s.occupation.name.include?("介護") }

            need_nurse = [counts[:nurse] - fixed_nurse - already_nurse, 0].max
            need_care  = [counts[:care]  - fixed_care - already_care,  0].max

            base_exclude = assigned_today.to_a + holiday_ids

            need_nurse.times do
              staff = pick_staff_for(:day, role: :nurse, exclude_ids: base_exclude, date: date)
              break if staff.nil?

              day_rows << { slot: slot, staff_id: staff.id }
              assigned_today.add(staff.id)
              slot += 1
              base_exclude = assigned_today.to_a + holiday_ids
            end

            need_care.times do
              staff = pick_staff_for(:day, role: :care, exclude_ids: base_exclude, date: date)
              break if staff.nil?

              day_rows << { slot: slot, staff_id: staff.id }
              assigned_today.add(staff.id)
              slot += 1
              base_exclude = assigned_today.to_a + holiday_ids
            end

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

    def pick_staff_for(kind, exclude_ids:, role: nil, date: nil) # ここでのexclude_ids：すでに選ばれた職員のID配列（同じ人を重複させないため）
      scope = @shift_month.user.staffs.where(active: true) # この月を作ったユーザーが登録している職員一覧をscopeに代入

      scope =                          # case kindで条件を足している。kindに応じて対応できる職員だけに絞る
        case kind
        when :day    then scope.where(can_day: true)
        when :early  then scope.where(can_early: true)
        when :late   then scope.where(can_late: true)
        when :night  then scope.where(can_night: true)
        else
          scope.none # 想定外のkindが来たら誰も返さない
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
        wday = ShiftMonth.ui_wday(date)
        scope = scope.left_joins(:staff_workable_wdays)
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

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?  # any?で配列に一つでも要素があればture. exclude_idsは含めない
      # ここまでで、kindがtrue かつ すでに使用したIDではない、の条件で満たされたscopeができる。

      scope.order(Arel.sql("RANDOM()")).first # Rails7以降、Arel.sqlとは生SQL文字列をそのまま渡すと警告が出るため、意図したSQLと明示
    end
  end
end

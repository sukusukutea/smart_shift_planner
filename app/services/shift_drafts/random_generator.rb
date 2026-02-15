module ShiftDrafts
  class RandomGenerator
    def initialize(shift_month:)
      @shift_month = shift_month
      @active_scope = @shift_month.user.staffs.where(active: true)
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month
      @month_end  = month_end
      @dates = (month_begin..month_end).to_a
      @staff_by_id = @active_scope.includes(:staff_workable_wdays, :occupation).index_by(&:id)

      @worked_days_by_staff, @last_worked_by_staff = build_worked_indexes(
        month_begin: month_begin,
        month_end: month_end
      )

      designations = @shift_month.shift_day_designations.where(date: month_begin..month_end)
      designations_by_date = Hash.new { |h, k| h[k] = {} }
      designations.each do |d|
        kind = d.shift_kind.to_s

        if kind == "late" || kind == "day"
          (designations_by_date[d.date][kind] ||= []) << d.staff_id
        else
          designations_by_date[d.date][kind] = d.staff_id
        end
      end # 返り値 designations_by_date[date]["day"] => staff_id　みたいに引ける形

      @designations_by_date = designations_by_date

      holiday_ids_by_date =
        @shift_month.staff_holiday_requests
                    .where(date: month_begin..month_end)
                    .group_by(&:date)
                    .transform_values { |rows| rows.map(&:staff_id) }

      draft = {}
      @timeline =
        ShiftDrafts::AssignmentTimeline.new(
          dates: (month_begin..month_end).to_a,
          staff_by_id: @staff_by_id,
          assignments_hash: draft
        )

      # staff_id => Ser[Date, Date, ...]この日の割当を禁止する
      @forced_off_dates_by_staff_id = Hash.new { |h, k| h[k] = Set.new }

      occ_name_by_staff_id = @active_scope
                             .joins(:occupation)
                             .pluck(:id, "occupations.name")
                             .to_h
 
      (month_begin..month_end).each do |date|
        # 前日までのdraftをtimelineに反映（連続勤務判定のため）
        @timeline.call

        enabled_map = @shift_month.enabled_map_for(date) # その日の勤務のON/OFFを取得 返り値例{ day: true, early: true, late: false, night: true }
        skill_counts = @shift_month.required_skill_counts_for(date)
        
        scope = @active_scope

        holiday_ids = holiday_ids_by_date[date] || []
        assigned_today = Set.new  # SetはRuby標準ライブラリのSetクラス「同じ値を二度入れられない」。同じidが重複できない
        day_hash = {} # その日の最終結果

        forced_off_ids = forced_off_staff_ids_on(date)

        ShiftMonth::SHIFT_KINDS.each do |kind|
          sid = designations_by_date.dig(date, kind.to_s)
          next if sid.blank?

          if kind == :late || kind == :day
            Array(sid).each do |staff_id|
              staff_id = staff_id.to_i
              rows = (day_hash[kind] ||= [])
              rows << { slot: rows.size, staff_id: staff_id }
              assigned_today.add(staff_id)
              track_work!(staff_id, date: date)
              after_assigned!(staff_id, date: date, kind: kind, month_end: @month_end)
            end
          else
            staff_id = sid.to_i
            rows = (day_hash[kind] ||= [])
            rows << { slot: rows.size, staff_id: staff_id }
            assigned_today.add(staff_id)
            track_work!(staff_id, date: date)
            after_assigned!(staff_id, date: date, kind: kind, month_end: @month_end)
          end
        end

        fill_order = [:early, :late, :day, :night]
        fill_order.each do |kind|
          next unless enabled_map[kind] # OFFなら割当しない
          # day以外は基本１枠。遅番のみ日別設定で２枠まで許可する
          if kind != :day
            limit = (kind == :late) ? @shift_month.late_slots_for(date) : 1
            next if Array(day_hash[kind]).size >= limit
          end

          if kind == :day
            counts = @shift_month.required_counts_for(date, shift_kind: :day)
            skill_counts = @shift_month.required_skill_counts_for(date)

            fixed_staffs = scope
              .where(can_day: true)
              .where(assignment_policy: :required)
              .left_joins(:staff_workable_wdays)
              .where(staff_workable_wdays: { wday: ShiftMonth.ui_wday(date) })
              .where.not(id: holiday_ids + forced_off_ids)
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
                track_work!(staff.id, date: date)
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
              track_work!(staff.id, date: date)
              after_assigned!(staff.id, date: date, kind: :day, month_end: @month_end)
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

            current_staff_ids = day_rows.map { |r| r[:staff_id] }.compact.map(&:to_i)
            have_nurse = current_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("看護") }
            have_care  = current_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("介護") }

            need_nurse = [counts[:nurse] - have_nurse, 0].max
            need_care  = [counts[:care]  - have_care,  0].max

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

          # 返り値：今日すでに使ったIDがいればStaffオブジェクト、いなければnil
          exclude_for_normal = assigned_today.to_a + holiday_ids + forced_off_ids
          staff = pick_staff_for(kind, exclude_ids: exclude_for_normal, date: date)

          # 夜勤候補が0なら「夜勤2連続」を例外で許可
          if staff.nil? && kind == :night
            staff = pick_staff_for_double_night(date: date, exclude_ids: assigned_today.to_a + holiday_ids)
          end

          next if staff.nil? # 候補0なら空欄

          (day_hash[kind] ||= []) << { slot: (day_hash[kind]&.size || 0), staff_id: staff.id }
          assigned_today.add(staff.id)
          track_work!(staff.id, date: date)
          after_assigned!(staff.id, date: date, kind: kind, month_end: @month_end)
        end

        draft[date.iso8601] = day_hash # １日のドラフトを格納
      end

      draft
    end
    
    private

    def apply_workday_constraint(scope, date:)
      wday = ShiftMonth.ui_wday(date)

      scope
        .left_joins(:staff_workable_wdays)
        .joins(<<~SQL.squish)
          LEFT OUTER JOIN staff_unworkable_wdays
            ON staff_unworkable_wdays.staff_id = staffs.id
           AND staff_unworkable_wdays.wday = #{ActiveRecord::Base.connection.quote(wday)}
        SQL
        .where(
          "(staffs.assignment_policy = :candidate
              AND staff_unworkable_wdays.wday IS NULL)
            OR
            (staffs.assignment_policy = :required
              AND staff_workable_wdays.wday = :wday)", # staff_unworkable_wdays.wday IS NULLは「その曜日がNG登録されていない人だけを通す」
          wday: wday,
          candidate: Staff.assignment_policies[:candidate],
          required:  Staff.assignment_policies[:required]
        )
        .distinct
    end

    # そのstaffがその日に「日勤系」で手動指定されているか？
    def designated_dayish?(staff_id, date)
      h = @designations_by_date&.[](date)
      return false if h.blank?

      sid = staff_id.to_i

      day = h["day"]
      return true if Array(day).any? { |x| x.to_i == sid }
      return true if h["early"].to_i == sid

      late = h["late"]
      Array(late).any? { |x| x.to_i == sid }
    end

    def consecutive_designation_days_after(staff_id, date)
      return 0 if date.nil?
      return 0 if @dates.blank? || @designations_by_date.blank?

      idx = @dates.index(date)
      return 0 unless idx

      count = 0
      @dates[(idx + 1)..].each do |d|
        if designated_dayish?(staff_id, d)
          count += 1
        else
          break
        end
      end
      count
    end

    # ここでのexclude_ids：すでに選ばれた職員のID配列（同じ人を重複させないため）
    def pick_staff_for(kind, exclude_ids:, role: nil, date: nil, skill: nil) 
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

      if date.present? && [:day, :early, :late].include?(kind)
        scope = apply_workday_constraint(scope, date: date)
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?  # any?で配列に一つでも要素があればture. exclude_idsは含めない
      # ここまでで、kindがtrue かつ すでに使用したIDではない、の条件で満たされたscopeができる。

      # 候補IDを取ってRuby側で「直近で働いていない順」→「勤務日数が少ない順」に並べて選ぶ
      candidate_ids = scope.pluck(:id)

      # 連続勤務5日→２休を強制（Timelineで判定）
      if date.present? && [:day, :early, :late].include?(kind)
        candidate_ids =
          candidate_ids.reject do |sid|
            before = @timeline.consecutive_day_count_before(sid, date)
            after  = consecutive_designation_days_after(sid, date)
            (before + 1 + after) > 5
          end
      end

      priority_mode =
        case kind
        when :early, :late
          :worked_only # 勤務日数を確認。勤務日数が少ない人を優先させるため。
        else
          :full # 最近働いていない人＋勤務日数を確認 優先順位①最近働いていない人②勤務日数が少ない人
        end

      pick_by_priority(candidate_ids, date: date, priority_mode: priority_mode)
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

      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      drive_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :drive)
      while need_drive > 0 && drive_ids.any?
        sid = drive_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        track_work!(sid, date: date)
        after_assigned!(sid, date: date, kind: :day, month_end: @month_end)
        slot += 1
        need_drive -= 1
      end

      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      cook_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :cook)
      while need_cook > 0 && cook_ids.any?
        sid = cook_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        track_work!(sid, date: date)
        after_assigned!(sid, date: date, kind: :day, month_end: @month_end)
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
      sort_ids_by_priority(scope.pluck(:id), date: date)
    end

    def fill_day_roles!(day_rows:, date:, need_nurse:, need_care:, assigned_today:, holiday_ids:, slot:)
      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      nurse_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :nurse)
      while need_nurse > 0 && nurse_ids.any?
        sid = nurse_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        track_work!(sid, date: date)
        after_assigned!(sid, date: date, kind: :day, month_end: @month_end)
        slot += 1
        need_nurse -= 1
      end
      
      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      care_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :care)
      while need_care > 0 && care_ids.any?
        sid = care_ids.pop
        day_rows << { slot: slot, staff_id: sid }
        assigned_today.add(sid)
        track_work!(sid, date: date)
        after_assigned!(sid, date: date, kind: :day, month_end: @month_end)
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
      sort_ids_by_priority(scope.pluck(:id), date: date)
    end

    # 日単位で「勤務日数」と「最終勤務日」を作る worked_days_by_staff => { staff_id => 12, ... }, last_worked_by_staff => { staff_id => Date, ... }
    def build_worked_indexes(month_begin:, month_end:) 
      worked = Hash.new(0)
      last  = {}

      [worked, last]
    end

    def pick_by_priority(candidate_ids, date:, priority_mode: :full)
      return nil if candidate_ids.blank?

      ids = sort_ids_by_priority(candidate_ids, date: date, priority_mode: priority_mode)

      @active_scope.find_by(id: ids.last)
    end

    def sort_ids_by_priority(ids, date:, priority_mode: :full)
      Array(ids).sort_by do |sid|
        worked = @worked_days_by_staff[sid].to_i

        case priority_mode
        when :worked_only # 純粋に勤務日数だけチェック
          [
            -worked, # 末尾が「勤務日数少ない人」にしたいので -worked(小→大で末尾が小さくなる)
            rand
          ]
        else # :full
          days_since = days_since_last_work(sid, date: date)
          [
            days_since,
            -worked,
            rand                                # 同点揺らぎ
          ]
        end
      end
    end

    def days_since_last_work(staff_id, date:)
      last = @last_worked_by_staff[staff_id]
      return 10_000 if last.nil?
      (date - last).to_i
    end

    def track_work!(staff_id, date:) #生成中の割り当てを評価用indexに反映
      return if staff_id.blank? || date.nil?
      sid = staff_id.to_i

      @worked_days_by_staff[sid] = @worked_days_by_staff[sid].to_i + 1
      prev = @last_worked_by_staff[sid]
      @last_worked_by_staff[sid] = prev.nil? ? date : [prev, date].max
    end

    def forced_off_staff_ids_on(date)
      @forced_off_dates_by_staff_id
        .select { |_sid, set| set.include?(date) }
        .keys
    end

    def after_assigned!(staff_id, date:, kind:, month_end:)
      return if staff_id.blank? || date.nil?
      kind = kind.to_sym

      # 夜勤が入ったら明け＋休みを強制OFFにする
      if kind == :night
        if night_assigned_on?(staff_id.to_i, date - 2)
          lock_after_double_night!(staff_id.to_i, date: date, month_end: month_end) # 明け + 2休
        else
          lock_night_flow!(staff_id.to_i, date: date, month_end: month_end) # 明け + 休
        end
        return
      end

      return unless [:day, :early, :late].include?(kind)

      #今日割当する直前までの連続日勤系数
      before = @timeline.consecutive_day_count_before(staff_id.to_i, date)

      if before >= 4
        lock_two_off_days!(staff_id.to_i, date: date, month_end: month_end)
      end
    end

    def lock_two_off_days!(staff_id, date:, month_end:)
      d1 = date + 1
      d2 = date + 2
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
    end

    def lock_night_flow!(staff_id, date:, month_end:)
      # 1日目夜勤入り、2日目明け、3日目休
      d1 = date + 1
      d2 = date + 2
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
    end

    # 夜勤候補0の時に2連続夜勤をピックアップ。条件：2日前に夜勤には一致える。4日前に夜勤に入っている場合はNG。
    def pick_staff_for_double_night(date:, exclude_ids:)
      return nil if date.nil?

      base_ids =
        @active_scope
          .where(can_night: true)
          .pluck(:id)
          .reject { |sid| exclude_ids.include?(sid.to_i) }
          .select { |sid| night_assigned_on?(sid, date - 2) }
          .reject { |sid| night_assigned_on?(sid, date - 4) }

      return nil if base_ids.blank?

      ids = sort_ids_by_priority(base_ids, date: date, priority_mode: :full)
      @active_scope.find_by(id: ids.last)
    end

    def night_assigned_on?(staff_id, date)
      return false if staff_id.blank? || date.nil?
      return false if @timeline.nil?

      daily = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return false if daily.blank?
      daily[date] == :night
    end

    def lock_after_double_night!(staff_id, date:, month_end:)
      d1 = date + 1
      d2 = date + 2
      d3 = date + 3
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d3 if d3 <= month_end
    end
  end
end

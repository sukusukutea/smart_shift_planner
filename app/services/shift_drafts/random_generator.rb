module ShiftDrafts
  class RandomGenerator
    def initialize(shift_month:)
      @shift_month = shift_month
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month

      draft = {}

      (month_begin..month_end).each do |date|
        enabled_map = @shift_month.enabled_map_for(date) # その日の勤務のON/OFFを取得 返り値例{ day: true, early: true, late: false, night: true }

        assigned_today = Set.new                         # SetはRuby標準ライブラリのSetクラス「同じ値を二度入れられない」。同じidが重複できない
        day_hash = {} # その日の最終結果

        ShiftMonth::SHIFT_KINDS.each do |kind|
          next unless enabled_map[kind] # OFFなら割当しない

          staff = pick_staff_for(kind, exclude_ids: assigned_today.to_a)    # 返り値：今日すでに使ったIDがいればStaffオブジェクト、いなければnil
          next if staff.nil? # 候補0なら空欄

          day_hash[kind] = staff.id
          assigned_today.add(staff.id)
        end

        draft[date.iso8601] = day_hash # １日のドラフトを格納
      end

      draft
    end
    
    private

    def pick_staff_for(kind, exclude_ids:) # ここでのexclude_ids：すでに選ばれた職員のID配列（同じ人を重複させないため）
      scope = @shift_month.user.staffs # この月を作ったユーザーが登録している職員一覧をscopeに代入

      scope =                          # case kindで条件を足している。kindに応じて対応できる職員だけに絞る
        case kind
        when :day    then scope.where(can_day: true)
        when :early  then scope.where(can_early: true)
        when :late   then scope.where(can_late: true)
        when :night  then scope.where(can_night: true)
        else
          scope.none # 想定外のkindが来たら誰も返さない
        end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?  # any?で配列に一つでも要素があればture. exclude_idsは含めない
      # ここまでで、kindがtrue かつ すでに使用したIDではない、の条件で満たされたscopeができる。

      scope.order(Arel.sql("RANDOM()")).first # Rails7以降、Arel.sqlとは生SQL文字列をそのまま渡すと警告が出るため、意図したSQLと明示
    end
  end
end

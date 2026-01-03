module ShiftDrafts
  class StatsBuilder
    def initialize(shift_month:, staff_by_id:, draft:)
      @shift_month = shift_month
      @staff_by_id = staff_by_id
      @draft = draft
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month
      date_keys = (month_begin..month_end).map(&:iso8601)
      staff_ids = @staff_by_id.keys

      counts = Hash.new { |h, k| h[k] = Hash.new(0) } # counts[staff_id][:day] += 1 など kindの回数

      date_keys.each do |dkey|
        kinds = @draft[dkey] || {}
        kinds.each do |kind_sym_or_str, staff_id|
          next if staff_id.blank?
          kind = kind_sym_or_str.to_sym
          counts[staff_id.to_i][kind] += 1
        end
      end

      holiday_counts = Hash.new(0)
      date_keys.each do |dkey|
        assigned_ids = (@draft[dkey] || {}).values.compact.map(&:to_i)
        staff_ids.each do |sid|
          holiday_counts[sid] += 1 unless assigned_ids.include?(sid)
        end
      end

      staff_ids.sort_by { |sid|
        s = @staff_by_id[sid]
        [s.last_name_kana, s.first_name_kana]
      }
      .map { |sid|
        {
          staff: @staff_by_id[sid],
          day:   counts[sid][:day],
          early: counts[sid][:early],
          late:  counts[sid][:late],
          night: counts[sid][:night],
          holiday: holiday_counts[sid]
        }
      }
    end
  end
end
      
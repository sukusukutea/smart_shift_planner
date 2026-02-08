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

        kinds.each do |kind_sym_or_str, rows|
          kind = kind_sym_or_str.to_sym
          next unless ShiftMonth::SHIFT_KINDS.include?(kind)

          Array(rows).each do |row|
            staff_id = extract_staff_id(row)
            next if staff_id.nil?

            counts[staff_id.to_i][kind] += 1
          end
        end
      end

      total_days = date_keys.length
      worked_days = Hash.new(0)

      date_keys.each do |dkey|
        kinds = @draft[dkey] || {}
        assigned_ids =
          kinds.values
               .flat_map { |rows| Array(rows).map { |row| extract_staff_id(row) } }
               .compact
               .uniq

        prev_key = (Date.iso8601(dkey) - 1).iso8601
        prev = @draft[prev_key] || {}
        prev_night_first = Array(prev["night"] || []).first
        night_off_id = extract_staff_id(prev_night_first)

        assigned_ids << night_off_id if night_off_id.to_i > 0

        assigned_ids = assigned_ids.compact.uniq

        assigned_ids.each do |sid|
          worked_days[sid] += 1
        end
      end

      required_holidays = @shift_month.holiday_days.to_i

      staff_ids.sort_by { |sid|
        s = @staff_by_id[sid]
        [s.last_name_kana, s.first_name_kana]
      }
      .map { |sid|
        staff = @staff_by_id[sid]
        holiday_count = total_days - worked_days[sid]
        is_free = staff.respond_to?(:workday_constraint) && staff.workday_constraint == "free"
        holiday_shortage = is_free && required_holidays > 0 && holiday_count.to_i < required_holidays

        {
          staff: staff,
          day:   counts[sid][:day],
          early: counts[sid][:early],
          late:  counts[sid][:late],
          night: counts[sid][:night],
          holiday: holiday_count,
          holiday_shortage: holiday_shortage
        }
      }
    end

    private

    def extract_staff_id(row)
      return nil if row.nil?

      if row.is_a?(Hash)
        v = row["staff_id"] || row[:staff_id] # v:valueの略
        v.present? ? v.to_i : nil
      else
        row.present? ? row.to_i : nil
      end
    end
  end
end
      
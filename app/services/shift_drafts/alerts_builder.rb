module ShiftDrafts
  class AlertsBuilder
    def initialize(dates:, draft:, staff_by_id:, required_by_date:, enabled_by_date:)
      @dates = dates
      @draft = draft
      @staff_by_id = staff_by_id
      @required_by_date = required_by_date
      @enabled_by_date = enabled_by_date
    end

    def call
      alerts = {}

      @dates.each do |date|
        list = []

        dkey = date.iso8601
        kinds_hash = @draft[dkey] || {}

        # ---- 日勤不足（day+early+lateを合算して看護/介護を数える）----
        if enabled?(:day, date)
          req = @required_by_date[date] || { nurse: 0, care: 0 }
          req_nurse = req[:nurse].to_i
          req_care = req[:care].to_i

          if req_nurse > 0 || req_care > 0
            actual = day_actual_counts(kinds_hash)
            lack_nurse = [req_nurse - actual[:nurse], 0].max
            lack_care  = [req_care - actual[:care],   0].max

            if lack_nurse > 0 || lack_care > 0
              parts = []
              parts << "看#{lack_nurse}不足" if lack_nurse > 0
              parts << "介#{lack_care}不足"  if lack_care  > 0
              list << "日勤：#{parts.join(' ')}"
            end
          end
        end

        # ---- 早番/遅番/夜勤不足（ONなのに1人も入っていない）----
        list << "早番不足" if enabled?(:early, date) && blank_kind?(kinds_hash, "early")
        list << "遅番不足" if enabled?(:late, date)   && blank_kind?(kinds_hash, "late")
        list << "夜勤不足" if enabled?(:night, date) && blank_kind?(kinds_hash, "night")

        alerts[date] = list
      end

      alerts
    end

    private

    def enabled?(kind_sym, date)
      map = @enabled_by_date[kind_sym]
      return false if map.nil?
      map[date] == true
    end

    def blank_kind?(kinds_hash, kind_str)
      rows = kinds_hash[kind_str] || kinds_hash[kind_str.to_sym]
      Array(rows).empty?
    end

    # day/early/late の rows から occupation を見て nurse/care を数える
    def day_actual_counts(kinds_hash)
      nurse = 0
      care = 0

      %w[day early late].each do |kind|
        Array(kinds_hash[kind]).each do |row|
          sid = extract_staff_id(row)
          next if sid.nil?

          staff = @staff_by_id[sid.to_i]
          next if staff.nil?
          occ_name = staff.occupation&.name.to_s

          nurse += 1 if occ_name.include?("看護")
          care  += 1 if occ_name.include?("介護")
        end
      end

      { nurse: nurse, care: care }
    end

    def extract_staff_id(row)
      return nil if row.nil?
      return row.to_i unless row.is_a?(Hash)

      v = row["staff_id"] || row[:staff_id]
      v.present? ? v.to_i : nil
    end
  end
end

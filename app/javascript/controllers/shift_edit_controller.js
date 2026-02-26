import { Controller } from "@hotwired/stimulus"

// 役割：select変更 → 同じ行の表示(.shift-edit-display)更新 → debounceしてPATCH → 成功したら右サイドバー更新
export default class extends Controller {
  connect() {
    this._saveTimer = null
  }

  change(event) {
    const select = event.target
    if (!select) return

    const row = select.closest(".shift-edit-row")
    const display = row ? row.querySelector(".shift-edit-display") : null
    if (!display) return

    const nameBase = select.dataset.staffName || ""
    const raw = select.value // "early" / "late" / "off" / "day:12"
    const isOff = (raw === "off")

    let kind = raw
    let staffDayTimeOptionId = null
    if (raw && raw.startsWith("day:")) {
      kind = "day"
      const parts = raw.split(":")
      staffDayTimeOptionId = parts[1] ? parseInt(parts[1], 10) : null
    }

    // 表示用の時間文字列（optionのdata-time-textを優先）
    let timeText = ""
    const selectedOpt = select.options[select.selectedIndex]
    const optTime = selectedOpt ? selectedOpt.dataset.timeText : ""

    if (kind === "early") timeText = "(730-1630)"
    if (kind === "late")  timeText = "(11-20)"
    if (kind === "day" && optTime) timeText = `(${optTime})`

    display.classList.toggle("is-off", isOff)

    let nameEl = display.querySelector(".shift-edit-name")
    if (!nameEl) {
      nameEl = document.createElement("span")
      nameEl.className = "shift-edit-name"
      display.appendChild(nameEl)
    }
    nameEl.textContent = `${nameBase}${isOff ? "(休)" : ""}`

    let timeEl = display.querySelector(".shift-edit-time")
    if (timeText) {
      if (!timeEl) {
        timeEl = document.createElement("span")
        timeEl.className = "shift-edit-time"
        display.appendChild(timeEl)
      }
      timeEl.textContent = timeText
    } else {
      if (timeEl) timeEl.remove()
    }

    this.queueSave(select, { kind, staffDayTimeOptionId })
  }

  queueSave(select, payload) {
    if (this._saveTimer) clearTimeout(this._saveTimer)
    this._saveTimer = setTimeout(() => this.save(select, payload), 400)
  }

  async save(select, payload) {
    const url = select.dataset.updateUrl
    if (!url) return

    const staffId = select.dataset.staffId
    const date = select.dataset.date

    const kind = payload && payload.kind ? payload.kind : select.value
    const staffDayTimeOptionId =
      (payload && payload.staffDayTimeOptionId) ? payload.staffDayTimeOptionId : null


    const row = select.closest(".shift-edit-row")
    const display = row ? row.querySelector(".shift-edit-display") : null
    if (display) {
      display.classList.remove("is-save-error")
      display.classList.add("is-saving")
    }

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    try {
      const res = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          date: date,
          staff_id: staffId,
          kind: kind,
          staff_day_time_option_id: staffDayTimeOptionId
        })
      })

      const data = await res.json().catch(() => null)

      if (!res.ok || !data || data.ok !== true) {
        if (display) {
          display.classList.add("is-save-error")
          display.title = (data && data.error) ? data.error : "保存に失敗しました"
        }
        return
      }

      if (display) display.title = ""

      // 右サイドバー(stats)を更新
      if (data.stats_html) {
        const box = document.getElementById("draft-sidebar")
        if (box) box.innerHTML = data.stats_html
      }

      if (data.alerts_html_by_date) {
        Object.entries(data.alerts_html_by_date).forEach(([dateStr, html]) => {
          const el = document.getElementById(`alert-cell-${dateStr}`)
          if (el) el.innerHTML = html
        })
      }
    } catch (_e) {
      if (display) {
        display.classList.add("is-save-error")
        display.title = "保存に失敗しました"
      }
    } finally {
      if (display) display.classList.remove("is-saving")
    }
  }
}

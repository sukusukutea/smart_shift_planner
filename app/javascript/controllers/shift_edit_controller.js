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
    const v = select.value // "day" / "early" / "late" / "off"
    const isOff = (v === "off")

    let timeText = ""
    if (v === "early") timeText = "(730-1630)"
    if (v === "late") timeText = "(11-20)"

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

    this.queueSave(select)
  }

  queueSave(select) {
    if (this._saveTimer) clearTimeout(this._saveTimer)
    this._saveTimer = setTimeout(() => this.save(select), 400)
  }

  async save(select) {
    const url = select.dataset.updateUrl
    if (!url) return

    const staffId = select.dataset.staffId
    const date = select.dataset.date
    const kind = select.value

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
          kind: kind
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

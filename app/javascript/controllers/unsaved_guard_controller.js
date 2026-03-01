import { Controller } from "@hotwired/stimulus"

// data-controller="unsaved-guard"
// data-unsaved-guard-dirty-value="true|false"
// data-unsaved-guard-allow-urls-value="..."（スペース区切り）
// data-unsaved-guard-message-value="..."
export default class extends Controller {
  static values = {
    dirty: { type: Boolean, default: false },
    allowUrls: String,
    message: { type: String, default: "保存されていませんが移動します。よろしいですか？" }
  }

  connect() {
    this.onBeforeVisit = this.onBeforeVisit.bind(this)
    this.onBeforeUnload = this.onBeforeUnload.bind(this)

    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("beforeunload", this.onBeforeUnload)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
  }

  // --- 外部から呼べる（data-actionで使う） ---
  markDirty() {
    this.dirtyValue = true
  }

  markClean() {
    this.dirtyValue = false
  }

  // --- ガード本体 ---
  onBeforeVisit(event) {
    if (!this.dirtyValue) return

    const url = event.detail?.url
    if (!url) return

    if (this.isAllowed(url)) return

    const ok = window.confirm(this.messageValue)
    if (!ok) event.preventDefault()
  }

  onBeforeUnload(event) {
    if (!this.dirtyValue) return

    event.preventDefault()
    event.returnValue = ""
  }

  isAllowed(url) {
    const allowList = (this.allowUrlsValue || "")
      .split(/\s+/)
      .map(s => s.trim())
      .filter(Boolean)

    // Turbo から来るURLを pathname に正規化（絶対URLでも相対でもOKにする）
    const targetPath = new URL(url, window.location.origin).pathname

    return allowList.some((allowed) => {
      const allowedPath = new URL(allowed, window.location.origin).pathname
      return targetPath === allowedPath
    })
  }
}
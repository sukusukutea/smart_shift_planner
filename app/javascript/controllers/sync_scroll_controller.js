import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["main", "sticky", "stickyInner"]

  connect() {
    this.syncing = false
    this.refresh()
    window.addEventListener("resize", this.refreshBound = this.refresh.bind(this))
  }

  disconnect() {
    window.removeEventListener("resize", this.refreshBound)
  }

  refresh() {
    const table = this.mainTarget.querySelector(".shift-calendar-month")
    if (!table) return

    this.stickyInnerTarget.style.width = `${table.scrollWidth}px`
  }

  scrollMain() {
    if (this.syncing) return
    this.syncing = true
    this.stickyTarget.scrollLeft = this.mainTarget.scrollLeft
    this.syncing = false
  }

  scrollSticky() {
    if (this.syncing) return
    this.syncing = true
    this.mainTarget.scrollLeft = this.stickyTarget.scrollLeft
    this.syncing = false
  }
}
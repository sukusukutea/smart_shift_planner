import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dayReq"]

  toggleDayReq(event) {
    const on = event.target.value === "1"
    if (this.hasDayReqTarget) {
      this.dayReqTarget.style.display = on ? "" : "none"
    }
  }
}

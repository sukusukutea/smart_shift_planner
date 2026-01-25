import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dayReq"]

  connect() {
    const dayToggle = this.element.querySelector(
      'input[name="day_setting[enabled][:day]"]'
    )
    if (dayToggle && this.hasDayReqTarget) {
      this.dayReqTarget.style.display = dayToggle.checked ? "" : "none"
    }
  }

  toggleDayReq(event) {
    const on = event.target.checked
    if (this.hasDayReqTarget) {
      this.dayReqTarget.style.display = on ? "" : "none"
    }
  }
}

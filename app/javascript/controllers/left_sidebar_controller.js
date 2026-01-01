import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { collapsed: Boolean }

  connect() {
    this.apply()
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.apply()
  }

  apply() {
    document.body.classList.toggle("sidebar-left-collapsed", this.collapsedValue)
  }
}

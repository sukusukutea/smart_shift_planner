import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    speed: { type: Number, default: 1 } // ドラッグ感度
  }

  connect() {
    this.isDown = false
    this.startX = 0
    this.startScrollLeft = 0
    this.scrollTarget = this.element.closest(".shift-calendar-viewport")
  }

  down(event) {
    if (!this.scrollTarget) return

    this.isDown = true
    this.element.classList.add("is-dragging")

    this.startX = event.pageX
    this.startScrollLeft = this.scrollTarget.scrollLeft
  }

  move(event) {
    if (!this.isDown || !this.scrollTarget) return
    event.preventDefault()

    const dx = event.pageX - this.startX
    this.scrollTarget.scrollLeft = this.startScrollLeft - dx * this.speedValue
  }

  up() {
    this.isDown = false
    this.element.classList.remove("is-dragging")
  }

  leave() {
    this.up()
  }
}

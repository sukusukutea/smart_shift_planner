import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    speed: { type: Number, default: 1 } // ドラッグ感度
  }

  connect() {
    this.isDown = false
    this.startX = 0
    this.startScrollLeft = 0
  }

  down(event) {
    // 右クリックやフォーム要素上のドラッグは無視したい場合はここで制御できる
    this.isDown = true
    this.element.classList.add("is-dragging")

    this.startX = event.pageX
    this.startScrollLeft = this.element.scrollLeft
  }

  move(event) {
    if (!this.isDown) return
    event.preventDefault() // 文字選択を抑止

    const dx = event.pageX - this.startX
    this.element.scrollLeft = this.startScrollLeft - dx * this.speedValue
  }

  up() {
    this.isDown = false
    this.element.classList.remove("is-dragging")
  }

  leave() {
    this.up()
  }
}

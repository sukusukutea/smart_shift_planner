import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.isDown = false
    this.startX = 0
    this.scrollLeft = 0

    this.element.addEventListener("mousedown", this.onMouseDown)
    this.element.addEventListener("mouseleave", this.onMouseLeave)
    this.element.addEventListener("mouseup", this.onMouseUp)
    this.element.addEventListener("mousemove", this.onMouseMove)
  }

  disconnect() {
    this.element.removeEventListener("mousedown", this.onMouseDown)
    this.element.removeEventListener("mouseleave", this.onMouseLeave)
    this.element.removeEventListener("mouseup", this.onMouseUp)
    this.element.removeEventListener("mousemove", this.onMouseMove)
  }

  onMouseDown = (e) => {
    this.isDown = true
    this.element.classList.add("is-dragging")
    this.startX = e.pageX - this.element.offsetLeft
    this.scrollLeft = this.element.scrollLeft
  }
  onMouseLeave = () => {
    this.isDown = false
    this.element.classList.remove("is-dragging")
  }

  onMouseUp = () => {
    this.isDown = false
    this.element.classList.remove("is-dragging")
  }

  onMouseMove = (e) => {
    if (!this.isDown) return
    e.preventDefault()
    const x = e.pageX - this.element.offsetLeft
    const walk = (x - this.startX) * 1.2 //感度調整
    this.element.scrollLeft = this.scrollLeft - walk
  }
}
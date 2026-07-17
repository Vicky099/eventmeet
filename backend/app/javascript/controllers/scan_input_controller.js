import { Controller } from "@hotwired/stimulus"

// Phase 9 — check-in kiosk (requirement.md §3.7). A hardware barcode/RFID scanner behaves like a
// very fast keyboard: it types the identifier into the focused field, then an Enter keystroke —
// the form's own single text input + submit button already gets that Enter to submit natively
// (standard HTML implicit-submission behavior), no keydown handling needed here. This controller
// only owns the other half of a hands-off scan loop: keep the input focused on load, and clear +
// refocus it after every scan response (turbo:submit-end fires once the Turbo Stream response has
// been processed) so the next badge can be scanned immediately without touching the mouse.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.inputTarget.focus()
    this.element.addEventListener("turbo:submit-end", () => this.reset())
  }

  reset() {
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }
}

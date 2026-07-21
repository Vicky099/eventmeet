import { Controller } from "@hotwired/stimulus"

// Auto-dismissing confirmation banner for a successful check-in/out (checkin/_result.html.erb).
// scan.turbo_stream.erb re-renders this element on every scan via `update` (not `append`), so
// Stimulus's own connect() firing again on each fresh render is what restarts the countdown each
// time — no manual reset bookkeeping needed here.
const VISIBLE_MS = 3000

export default class extends Controller {
  connect() {
    requestAnimationFrame(() => this.element.classList.add("is-visible"))
    this.timeout = setTimeout(() => this.element.classList.remove("is-visible"), VISIBLE_MS)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}

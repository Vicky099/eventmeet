import { Controller } from "@hotwired/stimulus"

// Phase 4's tabbed event builder (requirement.md §5.2: "each tab autosaves independently — Turbo
// Frame per tab + background save"). The form this controls lives inside a <turbo-frame>, so
// requestSubmit() re-renders just that frame in place — the tab strip itself lives outside the
// frame and is untouched, and switching tabs client-side never interrupts an in-flight save.
export default class extends Controller {
  static values = { delay: { type: Number, default: 800 } }

  connect() {
    this.timeout = null
  }

  scheduleSave() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}

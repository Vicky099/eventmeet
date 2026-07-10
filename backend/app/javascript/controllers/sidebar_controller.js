import { Controller } from "@hotwired/stimulus"

// Ported from the webadmin template's app.js (vertical-menu-btn click handler + the
// DOMContentLoaded MetisMenu init) per requirement.md §5.14 — the template's own bundle assumes
// demo-only DOM (theme customizer, horizontal-layout twin markup) we don't ship, so rather than
// loading it wholesale we port just the two behaviors this app actually uses. MetisMenu itself
// (assets/libs/metismenujs) stays a small vendor script, loaded globally in the layout — this
// controller only owns wiring it up and the collapse toggle, not reimplementing it.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    if (this.hasMenuTarget && window.MetisMenu) {
      this.metisMenu = new MetisMenu(this.menuTarget)
    }
  }

  disconnect() {
    this.metisMenu?.dispose?.()
  }

  toggle() {
    document.body.classList.toggle("sidebar-enable")
  }
}

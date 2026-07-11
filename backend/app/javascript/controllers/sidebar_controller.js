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

    // turbo:before-render fires while the outgoing body is still on screen — restoring onto the
    // incoming body here, rather than in connect() (which only runs after Turbo has already
    // painted), avoids a one-frame flash of an expanded sidebar on every navigation while
    // collapsed.
    this.restoreSize = this.restoreSize.bind(this)
    document.addEventListener("turbo:before-render", this.restoreSize)
  }

  disconnect() {
    this.metisMenu?.dispose?.()
    document.removeEventListener("turbo:before-render", this.restoreSize)
  }

  // app.min.css's real desktop collapse mechanism is body[data-sidebar-size="sm"] (270px → 70px
  // icon rail) — .sidebar-enable only controls the *mobile* overlay
  // (`body.sidebar-enable .vertical-menu{display:block}`, the one rule that class actually has),
  // so toggling just that class — what this method used to do — had no visible effect at desktop
  // widths at all. Confirmed against the original template's own app.js (vendored wholesale, if
  // unused, by shopmate-backend at vendor/javascript/app.js) — this is the same handleSidebarToggle
  // logic, minus the sub-menu-reinit machinery that only matters once nested/collapsible nav
  // items exist (none do yet — flat top-level items only, see admin_nav_items/super_admin_nav_items).
  toggle() {
    document.body.classList.toggle("sidebar-enable")
    if (window.innerWidth < 992) return

    const next = document.body.getAttribute("data-sidebar-size") === "sm" ? "lg" : "sm"
    document.body.setAttribute("data-sidebar-size", next)
    try {
      localStorage.setItem("sidebar_size", next)
    } catch {
      // private browsing / storage disabled — collapse still works, just doesn't persist
    }
  }

  restoreSize(event) {
    if (window.innerWidth < 992) return
    let saved
    try {
      saved = localStorage.getItem("sidebar_size")
    } catch {
      return
    }
    if (saved) event.detail.newBody.setAttribute("data-sidebar-size", saved)
  }
}

import { Controller } from "@hotwired/stimulus"

// Persists which Bootstrap nav-pills tab is active in the URL hash — a refresh (or a shared/
// bookmarked link) lands back on the same tab instead of always resetting to the first one.
// history.replaceState, not pushState — switching tabs isn't a new "page" for the browser's own
// back button to step through.
export default class extends Controller {
  static targets = ["link"]

  connect() {
    const link = this.linkTargets.find((el) => el.getAttribute("href") === window.location.hash)
    if (link) bootstrap.Tab.getOrCreateInstance(link).show()

    this.element.addEventListener("shown.bs.tab", (event) => {
      history.replaceState(null, "", event.target.getAttribute("href"))
    })
  }
}

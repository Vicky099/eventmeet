import { Controller } from "@hotwired/stimulus"

// Admin::EventPagesController#edit's live preview pane (app/views/admin/event_pages/edit.html.erb)
// — drops the *current, unsaved* textarea contents straight into an iframe via `srcdoc`. Purely
// client-side, unlike email_template_preview_controller.js's own server round-trip: there's no
// token substitution to run server-side here (doc/public_event_site_options.md's Confirmed
// decision #2 — stored/rendered verbatim), so there's nothing to ask the server for. Debounced on
// every keystroke so typing feels live without thrashing the iframe; also on connect() so the pane
// isn't blank on first load.
export default class extends Controller {
  static targets = ["html", "frame"]

  connect() {
    this.refresh()
  }

  scheduleRefresh() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.refresh(), 500)
  }

  refresh() {
    this.frameTarget.srcdoc = this.htmlTarget.value
  }
}

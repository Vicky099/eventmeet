import { Controller } from "@hotwired/stimulus"

// Admin::EmailTemplatesController#edit's live preview pane (app/views/admin/email_templates/
// edit.html.erb) — posts the *current, unsaved* subject/HTML to #preview and drops the rendered
// result into an iframe via `srcdoc` (not `src` — there's no URL for content that hasn't been
// saved yet, same reasoning admin/badges' own preview iframe doesn't apply here since that one
// previews an already-persisted Badge). Debounced on every keystroke so typing feels live without
// firing a request per character; also on connect() so the pane isn't blank on first load.
export default class extends Controller {
  static targets = ["subject", "htmlBody", "subjectPreview", "frame"]
  static values = { url: String }

  connect() {
    this.refresh()
  }

  scheduleRefresh() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.refresh(), 500)
  }

  async refresh() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({
        subject: this.subjectTarget.value,
        html_body: this.htmlBodyTarget.value
      })
    })
    if (!response.ok) return

    const data = await response.json()
    this.subjectPreviewTarget.textContent = data.subject
    this.frameTarget.srcdoc = data.html
  }
}

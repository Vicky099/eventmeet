import { Controller } from "@hotwired/stimulus"

// requirement.md §4.3: reserved-word/uniqueness slug check "while typing" on the new/edit Account
// forms (SuperAdmin::AccountsController#new/#edit). Debounces the subdomain input and repoints
// the "slug_availability" Turbo Frame's `src` at #check_slug, which re-renders the availability
// state server-side — no client-side validation logic duplicated here.
export default class extends Controller {
  static targets = ["input", "frame"]
  static values = { url: String, excludeId: String }

  connect() {
    this.timeout = null
  }

  check() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      const slug = this.inputTarget.value.trim()
      let src = `${this.urlValue}?subdomain_slug=${encodeURIComponent(slug)}`
      // excludeId — edit form only, see _form.html.erb — so the record's own unchanged slug
      // doesn't come back flagged as "taken" against itself.
      if (this.hasExcludeIdValue) src += `&exclude_id=${encodeURIComponent(this.excludeIdValue)}`
      this.frameTarget.src = src
    }, 350)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}

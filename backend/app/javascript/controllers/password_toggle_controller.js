import { Controller } from "@hotwired/stimulus"

// Ported from the webadmin template's assets/js/pages/pass-addon.init.js — a small, page-specific
// (not Bootstrap-bundled) interaction, so per requirement.md §5.14 it's wired to Stimulus rather
// than loaded as a template-vendor script. First interactive component ported, per Phase 0.4/1.
export default class extends Controller {
  static targets = ["input", "icon"]

  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.iconTarget.classList.toggle("mdi-eye-outline", showing)
    this.iconTarget.classList.toggle("mdi-eye-off-outline", !showing)
  }
}

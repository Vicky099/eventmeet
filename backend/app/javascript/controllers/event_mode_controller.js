import { Controller } from "@hotwired/stimulus"

// Event.mode gates which location fields are meaningful (see Event#location_present_for_mode):
// address for on_site/hybrid, meeting_link for virtual/hybrid. Toggling visibility client-side
// avoids showing fields the mode doesn't need, without touching the server-side validation.
export default class extends Controller {
  static targets = ["mode", "onSiteField", "virtualField"]

  connect() {
    this.toggle()
  }

  toggle() {
    const mode = this.modeTarget.value
    this.onSiteFieldTargets.forEach((el) => el.classList.toggle("d-none", mode === "virtual"))
    this.virtualFieldTargets.forEach((el) => el.classList.toggle("d-none", mode === "on_site"))
  }
}

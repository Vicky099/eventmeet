import { Controller } from "@hotwired/stimulus"

// Agency#billing_cycle gates which contract fields are meaningful (Agency's own model comment:
// only the fields matching the selected billing_cycle are actually validated) — per_event's
// price_per_event/events_granted vs. annual's annual_price. Toggling visibility client-side
// mirrors event_mode_controller.js's identical shape for Event#mode/location fields.
export default class extends Controller {
  static targets = ["cycle", "perEventField", "annualField"]

  connect() {
    this.toggle()
  }

  toggle() {
    const cycle = this.cycleTarget.value
    this.perEventFieldTargets.forEach((el) => el.classList.toggle("d-none", cycle === "annual"))
    this.annualFieldTargets.forEach((el) => el.classList.toggle("d-none", cycle === "per_event"))
  }
}

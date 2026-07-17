import { Controller } from "@hotwired/stimulus"

// The Basic Info step's Settings card (requirement.md §5.3) — keeps `required` on the seat_limit
// input in sync with the "Seat Limit" toggle. The optional totalCountInput/totalSeatsDisplay
// targets are a holdover for any page that also wants a live running-total readout (none does
// right now — ticket categories' own "Total seats" field is gated server-side off the persisted
// event.has_seat_limit? instead, since the toggle lives on a different wizard step than the
// categories do); guarded with has*Target so this controller doesn't require them to connect.
//
// Showing/hiding the seat count field itself is handled entirely by CSS
// (`.seat-limit-block:has(#event_has_seat_limit:checked) .seat-limit-fields`, in
// application.css), not this controller — that stays correct instantly off the checkbox's own DOM
// state, with no dependency on Stimulus having connected yet. `required` can't be a CSS concern
// the same way: confirmed live that a `required` field hidden via display:none is NOT exempt from
// the browser's own constraint validation — it still blocks the whole form's submit, silently,
// with a console-only error ("An invalid form control ... is not focusable"). So `required` has
// to be actively kept in sync with visibility, not left for CSS/HTML defaults to sort out.
export default class extends Controller {
  static targets = ["toggle", "limitInput", "totalCountInput", "totalSeatsDisplay"]

  connect() {
    this.syncRequired()
    this.recompute()
  }

  syncRequired() {
    const on = this.toggleTarget.checked
    this.limitInputTarget.required = on
    this.totalCountInputTargets.forEach((input) => { input.required = on })
  }

  recompute() {
    if (!this.hasTotalSeatsDisplayTarget) return

    const total = this.totalCountInputTargets
      .filter((input) => !input.closest('[data-nested-fields-target="row"]')?.hidden)
      .reduce((sum, input) => sum + (parseInt(input.value, 10) || 0), 0)
    this.totalSeatsDisplayTarget.textContent = total
  }
}

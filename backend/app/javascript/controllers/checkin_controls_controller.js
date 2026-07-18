import { Controller } from "@hotwired/stimulus"

// Phase 9 revisit (requirement.md §3.7, §5.6) — the check-in kiosk's Direction (Check in/Check
// out/Print only), "Also print" and Session pickers are big, tappable pill/chip buttons, not a
// <select> (a mobile <select> dropdown is exactly the small-tap-target, extra-step friction this
// screen exists to avoid). Each group is a plain <button type="button"> row plus one paired
// hidden field carrying the actual value the form submits — this controller's job is keeping the
// two in sync: clicking a pill/chip marks it `.is-active` (and un-marks its siblings) and writes
// its `data-value` into the group's hidden field.
//
// requirement.md revisit: "once you set checkout and select session ... and we refresh the page
// then the selection will stay as it is." A plain server-rendered page always starts from the
// same defaults (Check in / Event entrance) on every GET — there's nothing server-side to
// remember a per-operator, per-desk choice against (no session/cookie state this kiosk keeps),
// so the choice is persisted client-side instead, in localStorage keyed by this event's id (not
// a single global key — a browser used for more than one event's check-in over time shouldn't
// leak one event's last-used session into another's). Restored on #connect, before the operator
// does anything, so a refresh mid-shift lands back where they left it.
//
// Phase 10 revisit — Print Agent (Electron) Integration (requirement.md §5.5.1): a second,
// independent pill-group ("Also print") joined the original single Direction pill-group, so
// every lookup here switched from the singular `pillGroupTarget`/`chipGroupTarget` Stimulus
// accessors (which only ever resolve the *first* matching element — silently wrong with more
// than one group present) to iterating `pillGroupTargets` and locating the specific group a
// click happened in via `closest(...)`. The per-field `localStorage` keying was already in place
// and needed no change — that's what makes this generalize safely.
export default class extends Controller {
  static targets = ["pillGroup", "chipGroup", "hiddenField", "printToggleWrap"]
  static values = { eventId: String }

  connect() {
    this.pillGroupTargets.forEach((group) => this.restore(group, "checkin-pill"))
    if (this.hasChipGroupTarget) this.restore(this.chipGroupTarget, "checkin-chip")
    this.syncPrintToggleVisibility()
  }

  selectPill(event) {
    const group = event.currentTarget.closest('[data-checkin-controls-target~="pillGroup"]')
    this.select(event, group, "checkin-pill")
    if (group.dataset.field === "scan_type") this.syncPrintToggleVisibility()
  }

  selectChip(event) {
    this.select(event, this.chipGroupTarget, "checkin-chip")
  }

  select(event, group, activeClass) {
    const value = event.currentTarget.dataset.value
    this.applySelection(group, activeClass, value)
    localStorage.setItem(this.storageKey(group.dataset.field), value)
  }

  restore(group, activeClass) {
    const stored = localStorage.getItem(this.storageKey(group.dataset.field))
    if (stored === null) return

    const button = Array.from(group.querySelectorAll(`.${activeClass}`)).find((el) => el.dataset.value === stored)
    if (!button) return // e.g. a session that no longer exists — keep the server-rendered default

    this.applySelection(group, activeClass, stored)
  }

  applySelection(group, activeClass, value) {
    group.querySelectorAll(`.${activeClass}`).forEach((el) => el.classList.toggle("is-active", el.dataset.value === value))

    const hiddenField = this.hiddenFieldTargets.find((field) => field.dataset.field === group.dataset.field)
    if (hiddenField) hiddenField.value = value
  }

  // requirement.md revisit: "print without marking attendance" (Direction: Print only) makes
  // "also print" redundant — printing is already what that direction does — so it's hidden
  // rather than left showing a toggle with no effect.
  syncPrintToggleVisibility() {
    if (!this.hasPrintToggleWrapTarget) return

    const directionGroup = this.pillGroupTargets.find((group) => group.dataset.field === "scan_type")
    const directionField = this.hiddenFieldTargets.find((field) => field.dataset.field === "scan_type")
    const isPrintOnly = directionGroup && directionField && directionField.value === "print"

    this.printToggleWrapTarget.classList.toggle("d-none", !!isPrintOnly)
  }

  storageKey(field) {
    return `checkin:${this.eventIdValue}:${field}`
  }
}

import { Controller } from "@hotwired/stimulus"

// Phase 6 — Ticketing (requirement.md §5.3): the Tickets step's ticket-category rows build up
// entirely client-side (no per-row save round trip) — this is what lets "Add another category"
// insert a blank row without touching the server, and "Remove" drop one, all before the whole
// form's own Next click actually persists anything (Admin::EventsController#update, Event
// accepts_nested_attributes_for :ticket_categories). Standard Rails nested-fields-via-<template>
// pattern (no gem): the template holds one row with a "NEW_RECORD" placeholder index, swapped for
// a real unique value on each add so Rails' array-of-hashes params parsing doesn't collide two
// new rows into the same key.
export default class extends Controller {
  static targets = ["container", "template", "row"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  // A row backed by a persisted record (TicketCategory or CustomField — this controller is
  // shared) carries a hidden id field — removing it has to submit `_destroy: "1"` alongside that
  // id (accepts_nested_attributes_for's allow_destroy) and merely hide the row, not delete it
  // from the DOM, or the id/_destroy pair never reaches the server at all. A brand-new row (added
  // via #add, never saved) has no id — nothing for the server to destroy, so it's safe to just
  // drop it from the DOM outright.
  //
  // The id field is NOT inside `row`: Rails' fields_for auto-inserts the nested-attributes hidden
  // id field as a SIBLING immediately after the partial's own markup for a persisted record, not
  // a descendant of it (confirmed live via the rendered HTML) — `row.querySelector` can never
  // find it. Derived from the `_destroy` field's own name instead (always present, same prefix)
  // and looked up in the row's parent, where Rails actually put it.
  remove(event) {
    event.preventDefault()

    const row = event.target.closest('[data-nested-fields-target="row"]')
    const destroyField = row.querySelector('input[name$="[_destroy]"]')
    const prefix = destroyField.name.slice(0, -"[_destroy]".length)
    const idField = row.parentElement.querySelector(`input[name="${prefix}[id]"]`)

    if (idField && idField.value) {
      destroyField.value = "1"
      row.hidden = true
      // A `required` field inside a `hidden` row still fails the browser's own constraint
      // validation on submit ("An invalid form control ... is not focusable") — display:none (or
      // the `hidden` attribute) does NOT exempt it, contrary to what the HTML5 spec's wording
      // about "not being rendered" might suggest; confirmed live, this silently blocks the whole
      // form's submit with no visible error. A row being removed is going away either way, so
      // nothing in it should be required anymore.
      row.querySelectorAll("[required]").forEach((field) => { field.required = false })
    } else {
      row.remove()
    }
  }
}

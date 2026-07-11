import { Controller } from "@hotwired/stimulus"

// Ported from shopmate-backend's confirm_dialog_controller.js (same template family) — intercepts
// a submit button's click, shows the shared Bootstrap modal (shared/_confirm_dialog.html.erb)
// instead of the browser's native confirm(), and only submits the button's form if the user
// confirms. data-controller="confirm-dialog" lives once on a shared ancestor (shared/
// _console_shell's #layout-wrapper), not on every trigger, so this reads data-message/data-title/
// data-danger off event.currentTarget (the clicked button) rather than `this.element` (which
// would resolve to that shared ancestor instead, not the button — a real bug the very first
// version of this had, caught by an actual click in a browser: the modal opened, but always with
// the generic "Confirm"/"Are you sure?" placeholder text, never the button's own data-message).
//
// Usage on a submit button inside its own form:
//   data-action="click->confirm-dialog#show"
//   data-message="Are you sure you want to do this?"
//   data-title="Confirm Action"          (optional, defaults to "Confirm")
//   data-danger="true"                   (optional, makes the confirm button red)
export default class extends Controller {
  show(event) {
    event.preventDefault()

    const trigger = event.currentTarget
    const message = trigger.dataset.message || "Are you sure?"
    const title = trigger.dataset.title || "Confirm"
    const danger = trigger.dataset.danger === "true"

    const modal = document.getElementById("confirmDialogModal")
    modal.querySelector("#confirmDialogTitle").textContent = title
    modal.querySelector("#confirmDialogMessage").textContent = message

    const okBtn = modal.querySelector("#confirmDialogOk")
    okBtn.className = `btn btn-sm ${danger ? "btn-danger" : "btn-primary"}`

    // Replace the button to wipe any previous confirmation's click listener rather than stacking
    // a new one on top each time the modal is reused for a different trigger.
    const freshBtn = okBtn.cloneNode(true)
    okBtn.replaceWith(freshBtn)

    freshBtn.addEventListener("click", () => {
      bootstrap.Modal.getInstance(modal).hide()
      const form = trigger.closest("form")
      if (form) {
        form.submit()
      } else if (trigger.href) {
        window.location.href = trigger.href
      }
    })

    new bootstrap.Modal(modal).show()
  }
}

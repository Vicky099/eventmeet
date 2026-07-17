import { Controller } from "@hotwired/stimulus"

// requirement.md §5.4/§5.14 v12 revisit: "when i select the ticket category then the form
// fields are not able to view below. ideally it should check the fields configured and then
// show the form." Repoints the participant_dynamic_fields Turbo Frame's `src` on the ticket
// category <select>'s change event, mirroring the existing slug_check_controller.js pattern —
// the server re-renders admin/participants/_dynamic_fields against the newly selected category.
export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String, participantId: String }

  refresh(event) {
    let src = `${this.urlValue}?ticket_category_id=${encodeURIComponent(event.target.value)}`
    if (this.hasParticipantIdValue && this.participantIdValue) {
      src += `&participant_id=${encodeURIComponent(this.participantIdValue)}`
    }
    this.frameTarget.src = src
  }
}

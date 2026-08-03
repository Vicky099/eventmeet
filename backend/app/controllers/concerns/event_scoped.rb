# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Shared by every
# Admin:: controller nested under an Event (RegistrationForms/Participants/ImportFiles/
# ExportFiles/ScanEvents) — previously each defined its own byte-identical private #set_event.
# Extracted now, not earlier, because `@event` finally has a second job beyond "the record this
# controller acts on": AdminHelper#event_nav_items / shared/_console_shell key off its presence to
# decide whether to render the account-level sidebar or the event-workspace one — a single shared
# place to set it is what makes that reliable across every controller that should trigger it,
# rather than each one remembering to set the same ivar under the same name by convention alone.
#
# Flat top-level name (not Admin::EventScoped), matching this app's existing concern-naming
# convention (PunditAuthorizable, PlatformRequestScoped, TenantResolvable) — none of those are
# namespaced under the audience they're actually specific to either, even though (like this one)
# they're only ever included from Admin:: or SuperAdmin:: controllers.
module EventScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_event
    before_action :require_event_approved!
  end

  private

  def set_event
    @event = Event.friendly.find(params[:event_id])
  end

  # requirement.md revisit: "client also create event but event created by client requires a
  # agency approval. post that client will proceed with event management (registration, checkin
  # and all)" — every controller nested under an Event via this concern IS "management" in that
  # sense (Admin::ParticipantsController/ExportFilesController/ImportFilesController/
  # GovtIdImportFilesController/ScanEventsController/PrintStationsController/BulkPrintRunsController/
  # RegistrationFormsController, plus the standalone check-in kiosk — CheckinController includes
  # this concern too, this file's own class comment). Lives here, not on Admin::BaseController,
  # specifically so CheckinController (which does NOT inherit from Admin::BaseController — its own
  # class comment on why) gets it for free the same way it already gets set_event.
  #
  # Blocks every role, including event_admin — approval isn't a permission gap the way
  # #require_staff_permission! (Admin::BaseController) restricts, it's "this event doesn't exist
  # yet as far as *operating* it goes." Deliberately never wired into Admin::EventsController
  # itself (not `EventScoped` — that controller sets `@event` in its own before_action, predating
  # this concern's extraction): the wizard (#edit/#update, and every other controller that
  # authorizes through EventPolicy#update? — Sessions/Speaker/Schedule/Badges/TicketReservations)
  # stays open regardless of approval_status — see that policy method's own comment for why the
  # client has to be able to keep *building* the event before the agency has anything to review,
  # and (once rejected) to fix and resubmit. #show (Analytics/status landing page, where the
  # pending/rejected banner lives) stays reachable too. Admin::EventsController#publish is the
  # wizard side's own separate approval gate — the event can be fully built, just not made live,
  # until approved.
  def require_event_approved!
    return unless @event.approval_pending? || @event.approval_rejected?

    redirect_to admin_event_path(@event), alert: "#{@event.name} is awaiting agency approval before it can be managed."
  end
end

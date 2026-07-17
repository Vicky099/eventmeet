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
  end

  private

  def set_event
    @event = Event.friendly.find(params[:event_id])
  end
end

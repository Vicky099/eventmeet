# Phase 4 (requirement.md §5.1): tenant isolation itself is TenantScoped's job (every Event a
# controller can even load is already this Account's own) — this is purely role-based visibility
# *within* the tenant. Any AccountMembership role can view; only event_admin can create/edit/
# destroy (the merged owner+event_manager tier — requirement.md revisit, Agency layer role remap).
class EventPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = event_admin?
  # requirement.md revisit: "once event complete the tenant can not able to edit the event" — a
  # completed event is history (attendance already happened, its own invoice generates the day
  # after — InvoiceGenerationJob), not a draft still being configured. Locked for every
  # AccountMembership role, not just a lesser one — event_admin is already the tenant's highest
  # tier, so there's no more-privileged role this could instead be relaxed to. Also gates #publish
  # (Admin::EventsController#publish authorizes via :update?) — moot in practice, since
  # Event#publish! only ever fires on a still-draft event and nothing here un-publishes a
  # completed one anyway, but keeps the one true "can this event still be changed" check in one place.
  #
  # requirement.md revisit: "client also create event but event created by client requires a
  # agency approval" — deliberately does NOT also gate on `approval_pending?`/`approval_rejected?`
  # here, unlike EventScoped#require_event_approved!'s own blanket block on the operational
  # surfaces (Participants/Export/Check-in/...): the client has to be able to actually *build* the
  # event — Basic Info through Review, Sessions/Speaker/Schedule/Badges — before the agency has
  # anything real to review at all, and (for a rejected one) to fix whatever was flagged and
  # resubmit. Admin::EventsController#publish is the real approval gate for the wizard side —
  # blocked separately there, not through this policy, so a `pending`/`rejected` event still
  # renders the same "Continue Setup" flow every other draft does, right up until Publish itself.
  def update? = event_admin? && !record.completed?
  def destroy? = event_admin?

  # PunditAuthorizable#user_not_authorized's optional per-query hook — nil (its own generic
  # "not authorized" message) when this event_admin was never allowed to edit events in the first
  # place; a specific message only for the one case worth distinguishing, the completed-event gate
  # above blocking someone who otherwise could.
  def update_reason
    return nil unless event_admin?

    "#{record.name} is completed and can no longer be edited." if record.completed?
  end
end

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
  def update? = event_admin? && !record.completed?
  def destroy? = event_admin?
end

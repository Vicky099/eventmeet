# Phase 8 (requirement.md §5.1): mirrors EventPolicy/ParticipantPolicy exactly — tenant isolation
# itself is TenantScoped's job; this is purely role-based visibility within a tenant. Any
# AccountMembership role can view; only event_admin can create/edit/destroy (the merged
# owner+event_manager tier — requirement.md revisit, Agency layer role remap). Badge (nested under
# Event) has no policy of its own — it delegates to this same EventPolicy-shaped check via the
# parent Event, same shortcut TicketCategory already takes.
class BadgeTemplatePolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = event_admin?
  def update? = event_admin?
  def destroy? = event_admin?
end

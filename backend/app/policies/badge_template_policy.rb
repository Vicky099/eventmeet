# Phase 8 (requirement.md §5.1): mirrors EventPolicy/ParticipantPolicy exactly — tenant isolation
# itself is TenantScoped's job; this is purely role-based visibility within a tenant. Any
# AccountMembership role can view; only owner/event_manager can create/edit; only owner can
# destroy. Badge (nested under Event) has no policy of its own — it delegates to this same
# EventPolicy-shaped check via the parent Event, same shortcut TicketCategory already takes.
class BadgeTemplatePolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = owner? || event_manager?
  def update? = owner? || event_manager?
  def destroy? = owner?

  private

  def event_manager?
    account_membership&.event_manager?
  end
end

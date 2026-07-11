# Phase 4 (requirement.md §5.1): tenant isolation itself is TenantScoped's job (every Event a
# controller can even load is already this Account's own) — this is purely role-based visibility
# *within* the tenant. Any AccountMembership role can view; only owner/event_manager can
# create/edit; only owner can destroy.
class EventPolicy < ApplicationPolicy
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

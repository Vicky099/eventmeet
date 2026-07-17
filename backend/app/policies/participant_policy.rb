# Phase 7 (requirement.md §5.1): mirrors EventPolicy exactly — tenant isolation itself is
# TenantScoped's job; this is purely role-based visibility within a tenant. Any AccountMembership
# role can view; only owner/event_manager can create/edit/import/export; only owner can destroy.
class ParticipantPolicy < ApplicationPolicy
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

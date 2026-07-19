# Phase 7 (requirement.md §5.1): mirrors EventPolicy exactly — tenant isolation itself is
# TenantScoped's job; this is purely role-based visibility within a tenant. Any AccountMembership
# role can view; only event_admin can create/edit/import/export/destroy (the merged
# owner+event_manager tier — requirement.md revisit, Agency layer role remap).
class ParticipantPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = event_admin?
  def update? = event_admin?
  def destroy? = event_admin?
end

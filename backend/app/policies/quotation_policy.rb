# Phase 15 (requirement.md §4.6, §5.1): mirrors BadgeTemplatePolicy exactly — Quotation is
# account-scoped directly (no Event parent, same reasoning as BadgeTemplate), tenant isolation
# itself is TenantScoped's job. Any AccountMembership role can view (including finance_readonly,
# §5.1's own "Finance/Read-only" role — this is exactly what it exists for); only owner/
# event_manager can request one or respond to it.
class QuotationPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = owner? || event_manager?
  def update? = owner? || event_manager?

  private

  def event_manager?
    account_membership&.event_manager?
  end
end

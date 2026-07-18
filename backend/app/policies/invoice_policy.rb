# Phase 15 (requirement.md §4.6, §5.1): mirrors QuotationPolicy — any AccountMembership role can
# view (finance_readonly's own use case, §5.1), only owner/event_manager can act ("Mark as Paid").
class InvoicePolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def update? = owner? || event_manager?

  private

  def event_manager?
    account_membership&.event_manager?
  end
end

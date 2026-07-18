# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5): same shape as PrintStationPolicy —
# any role can view a run's progress (a checkin_staff operator watching the batch at the desk),
# only owner/event_manager can start one.
class BulkPrintRunPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = owner? || event_manager?

  private

  def event_manager?
    account_membership&.event_manager?
  end
end

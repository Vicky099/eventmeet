# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5): same shape as PrintStationPolicy — any
# role can view a run's progress (an admin_staff operator watching the batch at the desk), only
# event_admin can start one (the merged owner+event_manager tier — requirement.md revisit, Agency
# layer role remap).
class BulkPrintRunPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = event_admin?
end

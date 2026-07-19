# Phase 10 (requirement.md §5.1, §5.5.1): mirrors BadgeTemplatePolicy/ParticipantPolicy exactly —
# any AccountMembership role can view (an admin_staff operator needs to see which stations exist to
# pick one), only event_admin can create/pair/revoke/destroy (the merged owner+event_manager tier —
# requirement.md revisit, Agency layer role remap) — pairing a station is as consequential as
# issuing any other credential in this app.
class PrintStationPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = event_admin?
  def update? = event_admin?
  def destroy? = event_admin?
end

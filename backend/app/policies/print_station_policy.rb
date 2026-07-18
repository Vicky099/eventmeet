# Phase 10 (requirement.md §5.1, §5.5.1): mirrors BadgeTemplatePolicy/ParticipantPolicy exactly —
# any AccountMembership role can view (a checkin_staff operator needs to see which stations exist
# to pick one), only owner/event_manager can create/pair/revoke/destroy — pairing a station is as
# consequential as issuing any other credential in this app.
class PrintStationPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = owner? || event_manager?
  def update? = owner? || event_manager?
  def destroy? = owner? || event_manager?

  private

  def event_manager?
    account_membership&.event_manager?
  end
end

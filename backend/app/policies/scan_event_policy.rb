# Phase 9 (requirement.md §5.1, §5.6). Mirrors EventPolicy/ParticipantPolicy's shape, but unlike
# either of those, checkin_staff needs real access here — the check-in kiosk is that role's entire
# reason to exist (requirement.md §5.1: "a check-in volunteer"). Admin::ScanEventsController
# authorizes against the parent Event (`authorize @event, policy_class: ScanEventPolicy`, same
# shortcut Admin::BadgesController already takes for Badge) rather than needing a real ScanEvent
# instance on hand for every action.
class ScanEventPolicy < ApplicationPolicy
  def index? = owner? || event_manager? || checkin_staff?
  def create? = owner? || event_manager? || checkin_staff?

  private

  def event_manager?
    account_membership&.event_manager?
  end

  def checkin_staff?
    account_membership&.checkin_staff?
  end
end

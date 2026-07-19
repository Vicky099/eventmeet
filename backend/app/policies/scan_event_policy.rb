# Phase 9 (requirement.md §5.1, §5.6). Mirrors EventPolicy/ParticipantPolicy's shape, but unlike
# either of those, admin_staff needs real access here — the check-in kiosk is that role's entire
# reason to exist (requirement.md §5.1: "a check-in volunteer"). Both remaining roles grant it
# (Agency layer role remap merged checkin_staff into admin_staff), so this is every
# AccountMembership role, same as index?/show? on the "any role can view" policies elsewhere — kept
# explicit rather than collapsed to `true` since this is a create-shaped action, not a plain view.
# Admin::ScanEventsController authorizes against the parent Event (`authorize @event,
# policy_class: ScanEventPolicy`, same shortcut Admin::BadgesController already takes for Badge)
# rather than needing a real ScanEvent instance on hand for every action.
class ScanEventPolicy < ApplicationPolicy
  def index? = event_admin? || admin_staff?
  def create? = event_admin? || admin_staff?
end

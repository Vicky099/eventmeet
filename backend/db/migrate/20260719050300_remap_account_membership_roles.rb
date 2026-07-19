# Confirmed with the user: collapses the 4-role tenant hierarchy (owner/event_manager/
# checkin_staff/finance_readonly) down to 2 (event_admin/admin_staff), to make room for the new
# agency_admin tier above it (see CreateAgencies/CreateAgencyMemberships). owner and event_manager
# already had identical Pundit grants everywhere in this app (every policy checked
# `owner? || event_manager?` as one unit, never one without the other) — same for checkin_staff and
# finance_readonly (both read/operate-only, never a create/edit grant) — so this is a real merge of
# already-equivalent permission sets, not a behavior change in disguise.
#
# Data migration (raw integer remap) runs before the model's enum declaration changes, so it reads
# the *old* enum's ordinals: owner(0)->event_admin(0), event_manager(1)->event_admin(0),
# checkin_staff(2)->admin_staff(1), finance_readonly(3)->admin_staff(1).
class RemapAccountMembershipRoles < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE account_memberships SET role = CASE role WHEN 0 THEN 0 WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 1 ELSE role END"
  end

  # Lossy by construction — event_admin(0) could have originally been owner(0) or event_manager(1);
  # this down arbitrarily restores owner/checkin_staff, the two lower ordinals, since there's no way
  # to recover which of the merged pair a given row actually was.
  def down
    execute "UPDATE account_memberships SET role = CASE role WHEN 0 THEN 0 WHEN 1 THEN 2 ELSE role END"
  end
end

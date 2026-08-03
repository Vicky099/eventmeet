# requirement.md revisit: "agency will define the client staff permission by toggle on or off and
# then based on permission staff will see the options in the client portal" — per-Account, not
# per-User/global (an agency sets this once for a tenant; every `admin_staff` AccountMembership on
# that tenant is gated the same way, `event_admin` never is — see Account::STAFF_PERMISSION_CATALOG
# and Account#staff_permission? for the read side).
#
# jsonb, not a real column per menu section: the catalog itself is expected to grow (a new
# Admin:: nav entry later needs a new toggle, not a new migration) — same "flexible catalog on a
# jsonb column" shape Event#participant_fields already established for its own toggleable set.
#
# default: {} + Account#staff_permission?'s own `.fetch(key, true)` fallback — every existing
# Account (and every new one, until an agency explicitly opens this settings panel) behaves
# exactly as it already does today: every AccountMembership role sees every section. This
# migration only adds the *capability* to restrict, it doesn't restrict anything on its own.
class AddStaffPermissionsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :staff_permissions, :jsonb, null: false, default: {}
  end
end

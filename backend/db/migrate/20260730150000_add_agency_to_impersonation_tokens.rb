# Agency Console impersonation (requirement.md revisit: "super admin should have option to
# impersonate agency and login to agency portal") — ImpersonationToken so far only ever targeted a
# tenant Account's own user (account_id null: false). An agency_admin has no AccountMembership at
# all, so the same "mint here, redeem there" mechanics now need to point at an Agency's own
# subdomain instead — account_id becomes optional, agency_id is the new alternative, and
# ImpersonationToken#account_or_agency_present enforces exactly one of the two is ever set (never
# both, never neither).
class AddAgencyToImpersonationTokens < ActiveRecord::Migration[8.0]
  def change
    change_column_null :impersonation_tokens, :account_id, true
    add_reference :impersonation_tokens, :agency, type: :uuid, foreign_key: true
  end
end

# requirement.md §4.9 item 4: one OAuth application per Account, auto-created by the Super Admin
# at tenant-provisioning time (Phase 2). unique index enforces the "one" — Doorkeeper::Application
# itself has no notion of a tenant.
class AddAccountToOauthApplications < ActiveRecord::Migration[8.0]
  def change
    add_reference :oauth_applications, :account, type: :uuid, null: false, foreign_key: true, index: { unique: true }
  end
end

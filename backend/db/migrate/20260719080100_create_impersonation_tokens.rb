# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Same shape as
# AccountSwitch (db/migrate/20260719070000_create_account_switches.rb) — short-lived, single-use,
# platform-level, no TenantScoped/RLS — but minted by a Super Admin targeting a *specific* tenant
# User, not self-serve by an agency admin switching into their own tenant. platform_staff (not
# "actor" — this table's own real-actor column, distinct from AuditLogEntry#actor) is who minted
# it; user is who gets signed in on redemption; account is which tenant subdomain it's redeemable
# on (same belt-and-suspenders host check AccountSwitch's own redeem action already does).
class CreateImpersonationTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :impersonation_tokens, id: :uuid, default: nil do |t|
      t.references :platform_staff, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at

      t.timestamps
    end

    add_index :impersonation_tokens, :token, unique: true
  end
end

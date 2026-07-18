# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3, §8). One row
# per successfully-redeemed pairing — the credential record a station-scoped JWT's `agent_id`
# claim points at. A PrintStation can accumulate several of these over its lifetime (revoke, then
# re-pair later) — "the currently active one" is the most recent non-revoked row
# (PrintStation#current_agent), not a 1:1 column on PrintStation itself, so pairing history isn't
# destroyed by a re-pair.
#
# jti (JWT ID) is the token's own unique claim — stored so a specific issued token can be looked
# up/invalidated independently of revoking the whole agent record, though this app's revocation
# model (checked live against `revoked_at` on every connect, requirement.md §5.5.1: "never given
# broader API access") doesn't currently need that distinction; kept for it to be possible later
# without a schema change.
#
# connected/last_seen_at back PrintStation#online? (requirement.md: "connection-status indicator
# per paired station (online/offline via Cable presence)") — toggled by PrintJobsChannel's
# subscribed/unsubscribed/heartbeat handling, not by anything else.
class CreatePrintAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :print_agents, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :print_station, null: false, type: :uuid, foreign_key: true

      t.string :jti, null: false
      t.datetime :paired_at, null: false
      t.datetime :revoked_at
      t.boolean :connected, null: false, default: false
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :print_agents, :jti, unique: true

    TenantRowLevelSecurity.enable!(self, :print_agents)
  end
end

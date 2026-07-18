# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). A PrintStation is
# the admin-facing "desk" (Station A → Printer 1) — it exists before any Electron agent has ever
# paired to it, created from the admin console so an admin has something to generate a pairing
# code against (PrintAgent, the next migration, is the record of an actual paired device).
#
# printer_name is free text, not a live-reported enum — the agent's own OS print spooler is the
# only thing that actually knows real printer names, and round-tripping that list back to the
# server (for a dropdown) is real, cross-platform-fragile work with no functional payoff over an
# admin just typing the name they already see on that machine; blank means "use the OS default
# printer" (Electron's webContents.print with no deviceName).
#
# pairing_code/pairing_code_expires_at live directly on the station rather than a separate table
# — only one pairing attempt is ever meaningful per station at a time (generating a new code
# implicitly invalidates whatever code was there before), so a second table would only ever hold
# a single active row per station anyway.
class CreatePrintStations < ActiveRecord::Migration[8.0]
  def change
    create_table :print_stations, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      t.string :printer_name
      t.string :pairing_code
      t.datetime :pairing_code_expires_at

      t.timestamps
    end

    # Globally unique, not per-tenant — a pairing code is presented to #pair before Current.account
    # is known (the Electron app hasn't authenticated as anything yet), so the lookup has to be a
    # bare, cross-tenant `find_by(pairing_code:)` (PrintStation.unscoped_across_tenants), same
    # reasoning Participant#hex_id's own global uniqueness comment gives for the same shape.
    add_index :print_stations, :pairing_code, unique: true, where: "pairing_code IS NOT NULL"

    TenantRowLevelSecurity.enable!(self, :print_stations)
  end
end

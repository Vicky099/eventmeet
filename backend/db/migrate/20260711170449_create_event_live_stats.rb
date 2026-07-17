# Phase 7 — Participant Lifecycle (requirement.md §8): "EventLiveStats row seeded/incremented on
# participant create (column exists, real-time broadcast wiring is Phase 9 — this phase just keeps
# the counter correct as a plain DB write)." All four counters requirement.md §8 describes
# (registered/checked-in/checked-out/occupancy) are created now so Phase 9 doesn't need another
# migration to add them — only registered_count is actually written to yet
# (Participant's after_create callback); the other three stay 0 until Phase 9's ScanEvent exists.
class CreateEventLiveStats < ActiveRecord::Migration[8.0]
  def change
    create_table :event_live_stats, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true, index: { unique: true }

      t.integer :registered_count, null: false, default: 0
      t.integer :checked_in_count, null: false, default: 0
      t.integer :checked_out_count, null: false, default: 0
      t.integer :occupancy_count, null: false, default: 0

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :event_live_stats)
  end
end

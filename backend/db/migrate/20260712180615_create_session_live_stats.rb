# Phase 11 (requirement.md §5.15, §8): "SessionLiveStats — per-session denormalized live
# counters ... the single read source for both a dashboard's initial load and its Action Cable
# broadcast payload" — mirrors EventLiveStats exactly (db/migrate/20260711170449_create_event_live_stats.rb),
# minus registered_count: there's no per-session registration event to seed it from (session
# check-in is capacity-gated against Session#seat_limit, not enrollment-gated — see Session's own
# model comment), only what actual check-in/check-out scans produce.
class CreateSessionLiveStats < ActiveRecord::Migration[8.0]
  def change
    create_table :session_live_stats, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :session, null: false, type: :uuid, foreign_key: true, index: { unique: true }

      t.integer :checked_in_count, null: false, default: 0
      t.integer :checked_out_count, null: false, default: 0
      t.integer :occupancy_count, null: false, default: 0

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :session_live_stats)
  end
end

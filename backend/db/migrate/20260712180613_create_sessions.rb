# Phase 11 (requirement.md §3.8, §5.6): "Sessions (breakout rooms/tracks) with independent seat
# capacity and their own check-in." Event-scoped, capacity shape mirrors TicketCategory's
# total_count/unlimited? convention (seat_limit nil = unlimited) rather than duplicating a second
# capacity idiom. `track` is the breakout-track label the Agenda time-grid groups columns by;
# `room` is separate (a track can run in different rooms across days) — both plain strings, no
# separate Track/Room model, since neither needs its own identity beyond a label.
class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      t.string :room
      t.string :track
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :seat_limit

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :sessions)
  end
end

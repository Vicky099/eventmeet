# Phase 9 (requirement.md §3.7, §5.6, §4.10). Attendance is the historical record derived from
# ScanEvent — "direction (event vs. session) and status tracked historically, not just as current
# state."
class CreateAttendances < ActiveRecord::Migration[8.0]
  def change
    create_table :attendances, id: :uuid, default: nil do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.references :participant, type: :uuid, null: false, foreign_key: true
      # ScanService always sets this; no scan is required to produce an Attendance row though
      # (EventCompletionService's manual_check_out/absent rows have no originating scan), hence
      # optional rather than null: false.
      t.references :scan_event, type: :uuid, foreign_key: true
      # event/session — :session is unused until Phase 11's Session model lands (checklist:
      # "sequence flexibly if needed" — the column exists now so that phase needs no migration of
      # its own, same trick Phase 7 used for EventLiveStats' checked_in/checked_out/occupancy
      # columns).
      t.integer :from, null: false, default: 0
      # check_in/check_out/manual_check_out/absent (requirement.md §3.7).
      t.integer :status, null: false, default: 0
      t.integer :time_spent_seconds
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :attendances, [ :event_id, :participant_id, :from, :status, :occurred_at ],
      name: "index_attendances_on_event_participant_from_status_occurred_at"
    add_index :attendances, [ :participant_id, :from, :status, :occurred_at ],
      name: "index_attendances_on_participant_from_status_occurred_at"

    TenantRowLevelSecurity.enable!(self, :attendances)
  end
end

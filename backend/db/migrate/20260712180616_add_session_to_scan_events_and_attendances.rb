# Phase 11 backfill (requirement.md §3.7, §3.8): session-level check-in — deferred by Phase 9
# because Session didn't exist yet (see ScanEvent/Attendance's own comments). `ALTER TABLE ADD
# COLUMN`/`ADD CONSTRAINT` on a partitioned parent table propagates to every existing partition
# and every partition attached later — the same mechanism the original account_id/event_id/
# participant_id foreign keys on these two tables already rely on (lib/monthly_range_partitioning.rb),
# so this needs no partition-by-partition work.
class AddSessionToScanEventsAndAttendances < ActiveRecord::Migration[8.0]
  def change
    add_reference :scan_events, :session, type: :uuid, foreign_key: true
    add_reference :attendances, :session, type: :uuid, foreign_key: true

    # Composite indexes covering the debounce/pairing queries once they're session-aware
    # (ScanService#debounced?, Attendance#compute_time_spent) — the existing (participant_id,
    # scan_type/from, ..., scanned_at/occurred_at) indexes from Phase 9 stay too, still used by
    # queries that don't care about session_id (event-level scans, where it's simply NULL).
    add_index :scan_events, [ :participant_id, :scan_type, :session_id, :scanned_at ],
      name: "index_scan_events_on_participant_type_session_scanned_at"
    add_index :attendances, [ :participant_id, :from, :session_id, :status, :occurred_at ],
      name: "index_attendances_on_participant_from_session_status"
  end
end

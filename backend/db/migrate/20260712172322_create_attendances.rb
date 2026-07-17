# Phase 9 (requirement.md §3.7, §5.6, §4.10). Attendance is the historical record derived from
# ScanEvent — "direction (event vs. session) and status tracked historically, not just as current
# state." Also monthly range-partitioned (on `occurred_at`), same reasoning as ScanEvent — see
# lib/monthly_range_partitioning.rb.
class CreateAttendances < ActiveRecord::Migration[8.0]
  def up
    MonthlyRangePartitioning.create_parent!(self, :attendances, partition_column: :occurred_at) do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.references :participant, type: :uuid, null: false, foreign_key: true
      # No foreign_key: true — scan_events' real uniqueness is the composite (id, scanned_at), and
      # Postgres can't add a foreign key against just one column of a partitioned table's
      # composite primary key. Plain indexed UUID column instead, enforced only at the
      # application layer (ScanService always sets it); see
      # lib/monthly_range_partitioning.rb's module comment for the general reasoning.
      t.uuid :scan_event_id
      # event/session — :session is unused until Phase 11's Session model lands (checklist:
      # "sequence flexibly if needed" — the column exists now so that phase needs no migration of
      # its own, same trick Phase 7 used for EventLiveStats' checked_in/checked_out/occupancy
      # columns).
      t.integer :from, null: false, default: 0
      # check_in/check_out/manual_check_out/absent (requirement.md §3.7).
      t.integer :status, null: false, default: 0
      t.integer :time_spent_seconds
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :attendances, [ :event_id, :participant_id, :from, :status, :occurred_at ],
      name: "index_attendances_on_event_participant_from_status_occurred_at"
    add_index :attendances, [ :participant_id, :from, :status, :occurred_at ],
      name: "index_attendances_on_participant_from_status_occurred_at"
    add_index :attendances, :scan_event_id
  end

  def down
    drop_table :attendances
  end
end

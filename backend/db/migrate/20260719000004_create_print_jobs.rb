# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). One row per print
# actually dispatched to a paired station — PrintTriggerService's own queue/status-tracking unit,
# "reuses the pattern from baseline's bulk-print failure tracking" per the checklist. Not
# monthly-partitioned like ScanEvent — this is a bounded-per-event queue (thousands of rows at
# the very most for a single large event), not an unbounded time-series log, so it follows the
# same plain-table shape Badge/Participant already do.
#
# bulk_print_run_id/sequence are both nullable — most PrintJobs come from a single manual/kiosk
# print (no run at all); only rows created by BulkPrintRunJob set both, sequence giving the batch
# a stable print order so BulkPrintRun#last_printed_participant means something concrete ("the
# highest-sequence succeeded job's participant"), not just "whichever one happened to update
# last" under concurrent agent acks.
class CreatePrintJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :print_jobs, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :print_station, null: false, type: :uuid, foreign_key: true
      t.references :participant, null: false, type: :uuid, foreign_key: true
      t.references :bulk_print_run, type: :uuid, foreign_key: true

      t.integer :sequence
      # pending/sent/succeeded/failed.
      t.integer :status, null: false, default: 0
      # manual/kiosk/bulk — mirrors ScanEvent#source's "who/what triggered this" shape, but a
      # distinct enum: a print job's own trigger taxonomy (single-button vs. check-in-desk vs.
      # batch run) doesn't map onto ScanEvent#source's kiosk/manual/agent/system values 1:1.
      t.integer :source, null: false, default: 0
      t.text :error_message

      t.datetime :sent_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :print_jobs, [ :bulk_print_run_id, :sequence ]

    TenantRowLevelSecurity.enable!(self, :print_jobs)
  end
end

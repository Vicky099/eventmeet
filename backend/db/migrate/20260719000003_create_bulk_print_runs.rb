# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue" feature,
# rebuilt against the real PrintStation/PrintJob infrastructure this phase introduces instead of
# the old server-`lpr` baseline). One row per "admin clicked Bulk Print with a batch limit" run.
#
# Deliberately no completed_count/last_printed_participant columns — both are computed off this
# run's own associated print_jobs (BulkPrintRun#completed_count/#last_printed_participant) so
# there's one source of truth (the PrintJob rows themselves) instead of a denormalized counter
# that could drift from what actually printed. Created before print_jobs (next migration) so
# print_jobs.bulk_print_run_id can be a real FK from the start, not a column added in a follow-up
# migration.
class CreateBulkPrintRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :bulk_print_runs, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :print_station, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.integer :limit, null: false
      # pending/processing/completed/failed — same shape ExportFile/ImportFile already use for an
      # async-job-backed progress page (BulkPrintRunJob, meta-refresh show page).
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :bulk_print_runs)
  end
end

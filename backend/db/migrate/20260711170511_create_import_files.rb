# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4): "Bulk XLSX import (async Sidekiq
# job)... progress-pollable." The uploaded .xlsx itself is an Active Storage attachment
# (ImportFile#file); this table tracks the job's own progress/outcome so the upload page can poll
# it — same per-row-outcome idea as the baseline, but summarized as counters rather than one row
# per participant (row_errors carries the few that actually need a human to see why).
class CreateImportFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :import_files, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      # pending/processing/completed/failed — failed means the job itself blew up (bad file,
      # unreadable format), not "some rows had errors" (those are per-row, tracked below;
      # completed with error_count > 0 is the normal "mixed file" outcome).
      t.integer :status, null: false, default: 0
      t.integer :total_rows
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      # Array of { row:, message: } — deliberately capped/summarized by the job, not one row per
      # error at unbounded scale (see ParticipantImportJob).
      t.jsonb :row_errors, null: false, default: []

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :import_files)
  end
end

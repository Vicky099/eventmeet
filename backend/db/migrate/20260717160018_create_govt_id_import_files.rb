# requirement.md revisit: "in upload we should have a separate sample xlsx file to upload the
# govtID." Same progress-pollable bulk-upload shape as ImportFile/ExportFile (Phase 7) — a
# dedicated table, not a `kind` column on ImportFile itself, matching this app's existing
# convention of one small table per distinct upload flow rather than one shared table
# discriminated by type. GovtIdImportJob tracks its own progress/outcome here; duplicate_count
# means "this value was already in the pool for this event," not a participant-dedupe concept.
class CreateGovtIdImportFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :govt_id_import_files, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.integer :status, null: false, default: 0
      t.integer :total_rows
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.jsonb :row_errors, null: false, default: []

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :govt_id_import_files)
  end
end

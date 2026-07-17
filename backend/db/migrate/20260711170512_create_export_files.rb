# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4): "bulk XLSX export... generated
# async and delivered via a signed cloud URL, with progress polling." The generated .xlsx is an
# Active Storage attachment (ExportFile#file) — Active Storage blob URLs are already signed/
# expiring by construction, so no separate signing mechanism is needed on top.
class CreateExportFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :export_files, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.integer :status, null: false, default: 0 # pending/processing/completed/failed

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :export_files)
  end
end

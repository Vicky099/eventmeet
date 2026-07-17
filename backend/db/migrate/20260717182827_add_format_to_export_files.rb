# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §3.11, §5.11): "Configurable
# export templates (organizer picks columns/format, including CSV/PDF, not just the fixed XLSX
# layout used today)." Phase 7 already generalized *columns* (ExportFile#fields) — this is the
# other half. `format`, not `file_format` — see ParticipantExportFields/Admin::
# ExportFilesController's own comment on the form's own field name: `format` is a reserved Rails
# routing/params concept (request format, e.g. a `.json` URL suffix), so the *form param* is
# `file_format` even though the column and model attribute stay the plain, obvious `format`.
class AddFormatToExportFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :export_files, :format, :integer, null: false, default: 0
  end
end

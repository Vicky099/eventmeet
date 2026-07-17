# requirement.md revisit: "Export sidebar button will provide a UI where admin can select the
# fields which he wants to export from the participant ... click on generate will generate and
# download the excel sheet." A jsonb array of field-key strings (same "jsonb array" shape
# ImportFile#row_errors already uses) — one ExportFile now remembers exactly which columns its
# own generated workbook carries, since that's chosen per-request on the new field-picker page
# (Admin::ExportFilesController#new) rather than being the same fixed column list every time.
# `default: []`, not nullable-with-no-default: ParticipantExportJob always reads this as an
# Array, never nil.
class AddFieldsToExportFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :export_files, :fields, :jsonb, null: false, default: []
  end
end

# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4). One row per bulk-import attempt —
# tracks ParticipantImportJob's progress/outcome so the upload page can poll it. The uploaded
# .xlsx itself is the Active Storage attachment; row-level detail beyond the summary counters
# lives in row_errors (capped, see ParticipantImportJob), not a table of its own.
class ImportFile < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment

  belongs_to :event
  belongs_to :created_by, class_name: "User"
  has_one_attached :file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  def percent_complete
    return 0 if total_rows.blank? || total_rows.zero?

    ((processed_rows.to_f / total_rows) * 100).round
  end

  def attach_tenant_scoped(uploaded_file)
    return if uploaded_file.blank?

    file.attach(
      io: uploaded_file,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type,
      key: tenant_scoped_blob_key("import_files", event_id, filename: uploaded_file.original_filename)
    )
  end
end

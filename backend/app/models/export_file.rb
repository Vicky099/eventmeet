# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4). One row per bulk-export request —
# tracks ParticipantExportJob's progress so the trigger page can poll it. The generated .xlsx is
# the Active Storage attachment; Active Storage blob URLs are already signed/expiring by
# construction, so `file` itself is the "signed cloud URL" delivery mechanism requirement.md asks
# for, not a separate signing step.
class ExportFile < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment

  belongs_to :event
  belongs_to :created_by, class_name: "User"
  has_one_attached :file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §3.11, §5.11): "organizer
  # picks columns/format, including CSV/PDF, not just the fixed XLSX layout used today."
  enum :format, { xlsx: 0, csv: 1, pdf: 2 }

  def attach_tenant_scoped(io:, filename:, content_type:)
    file.attach(
      io: io,
      filename: filename,
      content_type: content_type,
      key: tenant_scoped_blob_key("export_files", event_id, filename: filename)
    )
  end
end

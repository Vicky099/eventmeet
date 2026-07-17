# requirement.md revisit: "in upload we should have a separate sample xlsx file to upload the
# govtID." One row per bulk govt-ID-pool upload attempt — tracks GovtIdImportJob's progress/
# outcome so the upload page can poll it, the same shape ImportFile already uses for participant
# imports (Phase 7). duplicate_count here means "value already existed in this event's pool," not
# a participant-dedupe concept.
class GovtIdImportFile < ApplicationRecord
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
      key: tenant_scoped_blob_key("govt_id_import_files", event_id, filename: uploaded_file.original_filename)
    )
  end
end

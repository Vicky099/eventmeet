# requirement.md §4.2: Active Storage blobs live under a tenant-namespaced key, not the
# framework's own default random token — ActiveStorage::Blob has no account_id column of its own
# to scope by (it's a shared framework table, not one of ours), so the tenant boundary has to be
# enforced in the key/path itself. This also happens to be what makes Cloudinary folders land
# tenant-wise: Cloudinary treats every "/" in a blob key as a folder separator, so a key prefixed
# with the tenant's subdomain slug uploads into that tenant's own folder tree.
module TenantScopedAttachment
  extend ActiveSupport::Concern

  # Attaches `uploaded_file` to `public_send(attachment_name)`, under a tenant-namespaced blob key
  # built from *segments — shared by every has_one_attached slot in the app that isn't Active
  # Storage's framework-default random-token key: Badge/BadgeTemplate#background_image/#logo,
  # Participant#photo, Speaker#photo.
  #
  # `uploaded_file` is either an UploadedFile-shaped object (a plain server-relayed multipart
  # upload — still the fallback for any field not wired through the JS direct-upload flow, e.g.
  # Participant#document) or a signed_id String: Admin::DirectUploadsController already created
  # the Blob, under this exact key shape, and the browser already uploaded the actual bytes
  # straight to the storage service (image_upload_controller.js) — nothing left to relay through
  # this server at all, just attach the already-uploaded blob by its signed_id.
  def attach_tenant_scoped(attachment_name, uploaded_file, *segments)
    return if uploaded_file.blank?

    attachment = public_send(attachment_name)
    if uploaded_file.is_a?(String)
      blob = ActiveStorage::Blob.find_signed!(uploaded_file)
      ensure_blob_identified(blob)
      attachment.attach(blob)
    else
      attachment.attach(
        io: uploaded_file,
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type,
        key: tenant_scoped_blob_key(*segments, filename: uploaded_file.original_filename)
      )
    end
  end

  def tenant_scoped_blob_key(*segments, filename:)
    TenantScopedAttachment.blob_key(account, *segments, filename: filename)
  end

  private

  # Rails 8.0.5 bug (confirmed via reproduction): attaching a Blob that hasn't been identified
  # yet — the normal state for every direct-upload blob, since analysis is deliberately deferred
  # until first attach (Admin::DirectUploadsController creates it via
  # ActiveStorage::Blob.create_before_direct_upload!, before any bytes exist server-side to
  # analyze) — raises "ActiveRecord::ActiveRecordError: Cannot touch on a new or destroyed record
  # object" from deep inside ActiveStorage::Blob#touch_attachments. What actually happens: the
  # blob's own in-memory content_type/identified changes (set by
  # ActiveStorage::Attached::Changes::CreateOne#initialize's own blob.identify_without_saving
  # call) get autosaved mid-flight, while the brand-new join Attachment row is still being saved
  # for the very first time. Blob's `after_update :touch_attachments` callback fires at that exact
  # moment and, via bidirectional inverse_of association caching, finds and touches that
  # still-unsaved Attachment. Identifying (and persisting) the blob up front, before .attach ever
  # runs, means CreateOne#initialize's own identify_without_saving call becomes a no-op
  # (blob.identified? already true) — no pending blob changes left to autosave mid-attach, so the
  # buggy callback path never fires at all.
  def ensure_blob_identified(blob)
    return if blob.identified?

    blob.identify_without_saving
    blob.save! if blob.changed?
  end

  # Callable without an instance — Admin::DirectUploadsController needs to compute this exact same
  # key shape *before* any record exists to call the instance method above on (the direct-upload
  # flow creates the Blob first, from the browser, ahead of ever attaching it to a Badge/
  # Participant/Speaker that may not even be saved yet).
  def self.blob_key(account, *segments, filename:)
    ([ account.subdomain_slug ] + segments.map(&:to_s) + [ "#{SecureRandom.uuid}-#{filename}" ]).join("/")
  end
end

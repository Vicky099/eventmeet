# Structured Cloudinary folder support — mirrors the sibling shopmate-backend project's own
# config/initializers/cloudinary_folder.rb strategy: explicitly create the target folder via the
# Admin API *before* uploading, and pass `folder:` as its own signed upload param rather than
# relying on "/" characters inside `public_id` to imply folder structure.
#
# Why this matters (same reasoning as shopmate's own comment): a Cloudinary account in **Fixed
# Folder Mode** treats slashes in `public_id` as literal characters in the filename, not folder
# separators — the asset lands at the Media Library root regardless of how the key is built,
# unless `folder:` is passed as an explicit, separately-signed param. Passing `folder:` explicitly
# works correctly in both Fixed and Dynamic Folder Mode, so this isn't optional/defensive — it's
# the only reliable way to get real nested folders (`app/models/concerns/
# tenant_scoped_attachment.rb`'s "acme/participants/<event_id>/photo/<uuid>-file.jpg"-shaped keys)
# regardless of which mode the account ends up in.
#
# Unlike shopmate, eventmeet has no browser-direct-upload flow (every attachment goes through a
# server-side `.attach(io:, key:, ...)` call — Participant#attach_tenant_scoped, BadgeTemplate/
# Badge#attach_tenant_scoped_file, ImportFile/ExportFile#attach_tenant_scoped) — so this only needs
# to patch CloudinaryService#upload, the one choke point every one of those calls already goes
# through. No Thread.current plumbing or pre-signed direct-upload-URL splitting needed.
ActiveSupport.on_load(:active_storage_blob) do
  # Runs after config/initializers/cloudinary.rb's own on_load(:active_storage_blob) callback
  # (registered first — Rails loads config/initializers/*.rb alphabetically, and "cloudinary.rb"
  # sorts before "cloudinary_folder.rb" — so ActiveStorage::Service::CloudinaryService is already
  # required and defined by the time this runs).
  next unless defined?(ActiveStorage::Service::CloudinaryService)
  next if ActiveStorage::Service::CloudinaryService.method_defined?(:__upload_without_folder)

  ActiveStorage::Service::CloudinaryService.class_eval do
    alias_method :__upload_without_folder, :upload

    def upload(key, io, filename: nil, checksum: nil, **options)
      key_str = key.to_s
      key_folder, separator, bare_key = key_str.rpartition("/")

      if separator.empty?
        __upload_without_folder(key, io, filename: filename, checksum: checksum, **options)
      else
        # `@options[:folder]` is the service-level root every upload already gets
        # (config/storage.yml's `folder: "eventmeet/<%= Rails.env %>"`, separating environments
        # sharing one Cloudinary account) — the original #upload applies it via
        # `@options.merge(options)`, where an explicit `folder:` in `options` would win outright
        # and silently drop that root prefix rather than nesting under it. Combine them instead:
        # confirmed live that skipping this would land every tenant's uploads at
        # "acme/participants/..." instead of "eventmeet/development/acme/participants/...",
        # losing environment separation the moment a key contains a "/".
        folder = [ @options[:folder], key_folder ].reject(&:blank?).join("/")
        ensure_cloudinary_folder(folder)
        __upload_without_folder(bare_key, io, filename: filename, checksum: checksum, folder: folder, **options)
      end
    end

    private

    # Creates the folder hierarchy if it doesn't already exist (Cloudinary's Admin API creates
    # every intermediate level in one call, same as `mkdir -p`). Safe to call on every upload:
    # Cloudinary returns 409 for a folder that already exists, which the gem raises as
    # Cloudinary::Api::AlreadyExists — silently ignored, same as shopmate's own version. Folder
    # creation failing for any other reason (transient API issue, bad credentials) must never
    # block the actual upload — logged as a warning instead of raised.
    def ensure_cloudinary_folder(folder)
      Cloudinary::Api.create_folder(folder)
    rescue Cloudinary::Api::AlreadyExists
      # Folder already exists — nothing to do.
    rescue StandardError => e
      Rails.logger.warn("[Cloudinary] Could not create folder '#{folder}': #{e.message}")
    end
  end
end

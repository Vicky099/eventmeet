# **Bug fix**: the `cloudinary` gem's own ActiveStorage::Service::CloudinaryService#public_id
# double-appends the file extension for "raw" (non-image) resources — .xlsx included — whenever
# the blob key already ends in one, which every blob key in this app always does
# (TenantScopedAttachment.blob_key always embeds the original filename, extension included, as
# its own last path segment). That breaks every one of ActiveStorage's standard read paths for a
# raw attachment on this service — Blob#url, #download, #open, and anything built on top of them
# — each ends up pointed at "...xlsx.xlsx", a resource that was never actually stored under that
# name: confirmed live, straight against Cloudinary's own Admin API, that the *correctly*-keyed
# resource genuinely exists with the right byte count the whole time. First caught as a 404 on
# Admin::ExportFilesController's own download link; the exact same bug then surfaced a second way
# as an ActiveStorage::IntegrityError inside ParticipantImportJob's `blob.open` read of an
# uploaded import file — both are this one gem bug, not two unrelated ones.
#
# .download reconstructs the *correct* public_id itself (folder + the blob's own key, extension
# exactly once) and fetches it through Cloudinary's authenticated `/raw/download` admin endpoint
# (Cloudinary::Utils.private_download_url, a signed URL good for this one fetch) — sidesteps the
# gem's own broken URL builder entirely rather than trying to patch it. Falls back to a plain
# `blob.download` for any non-Cloudinary service (this app's own :test/:local Disk services, which
# don't have this bug at all), so every existing spec running against those is unaffected.
class CloudinaryRawFile
  def self.download(blob)
    return blob.download unless blob.service_name.to_s == "cloudinary"

    Net::HTTP.get(URI(private_download_url(blob)))
  end

  # Cloudinary::Service::CloudinaryService instances only expose their configured `folder`
  # (config/storage.yml) via the private @options ivar — no public reader for it — so this
  # reaches in directly rather than duplicating that same value as a second, driftable constant.
  def self.private_download_url(blob)
    folder = blob.service.instance_variable_get(:@options)[:folder]
    public_id = [ folder, blob.key ].compact.join("/")
    Cloudinary::Utils.private_download_url(public_id, nil, resource_type: resource_type_for(blob), type: "upload", attachment: true)
  end

  # **Bug fix**: hardcoding resource_type: "raw" here 404s ("Resource not found") for a real,
  # correctly-uploaded file whenever Cloudinary itself filed it under a *different* resource_type
  # bucket — confirmed live for a PDF export (Phase 14, ParticipantExportJob's own PDF format):
  # the file genuinely exists, just not where a hardcoded "raw" lookup was told to find it. This
  # must exactly mirror the cloudinary gem's own upload-time decision
  # (ActiveStorage::Service::CloudinaryService#content_type_to_resource_type,
  # lib/active_storage/service/cloudinary_service.rb in the `cloudinary` gem) — whatever
  # resource_type THAT function picked when the file was written is the only one Cloudinary will
  # ever have it filed under. `application/pdf` is "image" there (Cloudinary can render/transform
  # PDF pages), not "raw" like every xlsx/csv export this class was originally written for.
  def self.resource_type_for(blob)
    type, subtype = blob.content_type.to_s.split("/")
    case type
    when "video", "audio" then "video"
    when "text", "message" then "raw"
    when "application"
      case subtype
      when "pdf", "postscript" then "image"
      when "vnd.apple.mpegurl", "x-mpegurl", "mpegurl" then "video"
      else "raw"
      end
    else
      "image"
    end
  end
end

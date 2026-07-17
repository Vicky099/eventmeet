module Admin
  # This app's own authenticated, tenant-scoped replacement for
  # ActiveStorage::DirectUploadsController — lets an image field upload straight from the browser
  # to the storage service (Cloudinary), with real byte-level progress (see
  # app/javascript/controllers/image_upload_controller.js), instead of relaying the file through
  # this server. The stock direct-uploads controller can't be used as-is here: it has no way to
  # know which tenant/record/field an upload is for, so it can only ever hand back the framework's
  # own random-token blob key — this app's blobs are required to live under a tenant-namespaced
  # key instead (requirement.md §4.2, TenantScopedAttachment), which has to be computed
  # server-side, from Current.account (never trusted from the client).
  class DirectUploadsController < BaseController
    layout false

    # `scope[type]` is a small allowlist (SCOPE_SEGMENTS below), not an arbitrary client-supplied
    # path — a request can only ever land under one of the folder shapes this app actually
    # attaches to elsewhere. `scope[event_id]` (where the shape needs one) is looked up through
    # Current.account.events, the same TenantScoped default_scope every other controller already
    # relies on for isolation, so a request can't point an upload at another tenant's event.
    SCOPE_SEGMENTS = {
      "badge_background_image" => ->(event) { [ "events", event.id, "badges", "background_image" ] },
      "badge_template_background_image" => ->(_event) { [ "badge_templates", "background_image" ] },
      "participant_photo" => ->(event) { [ "participants", event.id, :photo ] },
      "speaker_photo" => ->(_event) { [ "speakers", :photo ] }
    }.freeze

    def create
      blob = ActiveStorage::Blob.create_before_direct_upload!(key: scoped_key, **blob_args)
      render json: direct_upload_json(blob)
    end

    private

    def blob_args
      @blob_args ||= params.require(:blob).permit(:filename, :byte_size, :checksum, :content_type).to_h.symbolize_keys
    end

    def direct_upload_json(blob)
      blob.as_json(root: false, methods: :signed_id).merge(
        direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload }
      )
    end

    # Mirrors the exact key shape each model's own server-relayed attach call already builds
    # (Badge/BadgeTemplate#attach_background_image/#attach_logo, Participant#attach_tenant_scoped,
    # Speaker#attach_photo, all via TenantScopedAttachment) — a direct-uploaded blob has to land
    # under the identical path shape, or the two upload paths would silently diverge into two
    # different folder trees for what's supposed to be the same kind of attachment.
    def scoped_key
      scope = params.require(:scope).permit(:type, :event_id).to_h.symbolize_keys
      builder = SCOPE_SEGMENTS.fetch(scope[:type].to_s) { raise ActionController::BadRequest, "unknown upload scope: #{scope[:type]}" }
      event = Current.account.events.find(scope[:event_id]) if scope[:event_id].present?

      TenantScopedAttachment.blob_key(Current.account, *builder.call(event), filename: blob_args.fetch(:filename))
    end
  end
end

module AgencyConsole
  # This console's own copy of Admin::DirectUploadsController (see that controller's own comment
  # for the full "why not the stock ActiveStorage direct-uploads route" reasoning) — needed now
  # that the payment-receipt upload (AgencyConsole::InvoicesController#submit_payment) auto-uploads
  # straight to Cloudinary the same way Participant#photo/#document already do, rather than a plain
  # relayed file_field_tag. A separate controller, not a shared one, because it's keyed off
  # Current.agency instead of Current.account — the two base controllers don't share an ancestor
  # closer than ApplicationController (Admin::BaseController's own class comment).
  class DirectUploadsController < BaseController
    layout false

    # `scope[type]` is a small allowlist (SCOPE_SEGMENTS below), not an arbitrary client-supplied
    # path. `scope[invoice_id]` is looked up through Invoice.for_agency(Current.agency) — the same
    # authorization boundary AgencyConsole::InvoicesController#set_invoice already uses — so a
    # request can't point an upload at another agency's invoice.
    SCOPE_SEGMENTS = {
      "invoice_receipt" => ->(invoice) { [ "invoices", invoice.event_id || "agency-contract" ] }
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

    # Mirrors the exact key shape Invoice#attach_receipt/#tenant_scoped_blob_key already builds
    # for the (still-supported) server-relayed path — a direct-uploaded blob has to land under the
    # identical shape, or the two upload paths would silently diverge into two different folder
    # trees for what's supposed to be the same kind of attachment. Keyed by Current.agency (not
    # the invoice's own tenant account, even for a per-event invoice) — every invoice this console
    # ever touches is reached through the agency's own subdomain now, never a tenant's.
    def scoped_key
      scope = params.require(:scope).permit(:type, :invoice_id).to_h.symbolize_keys
      builder = SCOPE_SEGMENTS.fetch(scope[:type].to_s) { raise ActionController::BadRequest, "unknown upload scope: #{scope[:type]}" }
      invoice = Invoice.for_agency(Current.agency).find(scope[:invoice_id])

      TenantScopedAttachment.blob_key(Current.agency, *builder.call(invoice), filename: blob_args.fetch(:filename))
    end
  end
end

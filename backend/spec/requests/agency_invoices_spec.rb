require "rails_helper"

# Invoices moved from the tenant Admin Console to the Agency Console entirely (requirement.md
# revisit: "we will only charge agency ... per event / Per Year" — the agency is who's actually
# billed, so it's who manages/pays every invoice, not each individual tenant). Companion to
# spec/models/invoice_spec.rb (Invoice.for_agency's own unit coverage isn't duplicated here) and
# spec/requests/super_admin_invoices_spec.rb (the Platform Console's own side, including who gets
# notified now).
RSpec.describe "Agency Console invoices", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "sparkle") }
  let!(:agency_admin) { create(:user, email: "admin@sparkle.example", password: "password123!") }

  before do
    create(:agency_membership, user: agency_admin, agency: agency)
    host! "sparkle.example.com"
    sign_in agency_admin, scope: :user
  end

  def create_event_for(account, **attrs)
    Current.account = account
    create(:event, account: account, status: :completed, **attrs)
  end

  describe "GET /agency/invoices" do
    it "lists per-event invoices across every one of this agency's own tenants, excluding drafts" do
      tenant_a = create(:account, agency: agency, name: "Tenant A")
      tenant_b = create(:account, agency: agency, name: "Tenant B")
      tenant_c = create(:account, agency: agency, name: "Tenant C")
      event_a = create_event_for(tenant_a, name: "Event A")
      event_b = create_event_for(tenant_b, name: "Event B")
      event_c = create_event_for(tenant_c, name: "Event C")
      Current.account = tenant_a
      create(:invoice, :awaiting_payment, event: event_a, account: tenant_a)
      Current.account = tenant_b
      create(:invoice, :awaiting_payment, event: event_b, account: tenant_b)
      Current.account = tenant_c
      create(:invoice, event: event_c, account: tenant_c) # default status: draft — not yet sent

      get agency_invoices_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tenant A — Event A")
      expect(response.body).to include("Tenant B — Event B")
      expect(response.body).not_to include("Event C")
    end

    it "never shows an invoice belonging to a different agency's tenant" do
      other_agency = create(:agency, subdomain_slug: "other")
      other_account = create(:account, agency: other_agency, name: "Other Tenant")
      other_event = create_event_for(other_account, name: "Other Event")
      Current.account = other_account
      create(:invoice, :awaiting_payment, event: other_event, account: other_account)

      get agency_invoices_path

      expect(response.body).not_to include("Other Event")
    end

    it "shows the agency's own annual-contract invoice for an annual agency" do
      annual_agency = create(:agency, :annual, subdomain_slug: "yearly")
      admin = create(:user, email: "admin@yearly.example")
      create(:agency_membership, user: admin, agency: annual_agency)
      host! "yearly.example.com"
      sign_in admin, scope: :user

      get agency_invoices_path

      expect(response.body).to include("Annual Contract")
    end
  end

  describe "GET /agency/invoices/:id and POST submit_payment" do
    it "shows a per-event invoice and accepts a UTR submission" do
      tenant = create(:account, agency: agency, name: "Acme Tenant")
      event = create_event_for(tenant, name: "Diwali Fest")
      Current.account = tenant
      invoice = create(:invoice, :awaiting_payment, event: event, account: tenant)

      get agency_invoice_path(invoice)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Diwali Fest")
      expect(response.body).to include("Acme Tenant")

      post submit_payment_agency_invoice_path(invoice), params: { utr_reference: "UTR999" }

      expect(response).to redirect_to(agency_invoices_path)
      Current.account = tenant
      expect(invoice.reload).to be_under_review
      expect(invoice.utr_reference).to eq("UTR999")
    end

    it "404s for an invoice belonging to a different agency's tenant" do
      other_agency = create(:agency, subdomain_slug: "other")
      other_account = create(:account, agency: other_agency)
      other_event = create_event_for(other_account)
      Current.account = other_account
      other_invoice = create(:invoice, :awaiting_payment, event: other_event, account: other_account)

      get agency_invoice_path(other_invoice)

      expect(response).to have_http_status(:not_found)
    end
  end

  # requirement.md revisit: "this should look like real invoice with download button. refer
  # invoice ui from super admin" — shared/invoice_document is the same partial
  # SuperAdmin::InvoicesController#show/#download already renders (spec/requests/
  # super_admin_invoices_spec.rb has that side's own PDF-streaming coverage); this only needs to
  # confirm the Agency Console's own route/action wires up to the exact same pipeline.
  describe "GET /agency/invoices/:id/download" do
    it "streams a real PDF as an attachment" do
      tenant = create(:account, agency: agency, name: "Acme Tenant")
      event = create_event_for(tenant, name: "Diwali Fest")
      Current.account = tenant
      invoice = create(:invoice, :awaiting_payment, event: event, account: tenant)

      get download_agency_invoice_path(invoice)

      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.body[0, 5]).to eq("%PDF-")
    end

    it "404s for an invoice belonging to a different agency's tenant" do
      other_agency = create(:agency, subdomain_slug: "other")
      other_account = create(:account, agency: other_agency)
      other_event = create_event_for(other_account)
      Current.account = other_account
      other_invoice = create(:invoice, :awaiting_payment, event: other_event, account: other_account)

      get download_agency_invoice_path(other_invoice)

      expect(response).to have_http_status(:not_found)
    end
  end

  # requirement.md revisit: "Transaction receipt ... implement auto upload same as photo and
  # document" — the payment-receipt field now auto-uploads straight to Cloudinary
  # (image_upload_controller.js) through AgencyConsole::DirectUploadsController, the same shape
  # Admin::DirectUploadsController already established for Participant#photo/#document, rather
  # than a plain relayed file_field_tag.
  describe "POST /agency/direct_uploads and receipt attach" do
    # Mirrors the exact real-world shape (Admin::DirectUploadsController create_before_direct_upload!
    # then a real browser PUT to storage) that caught the Rails 8.0.5 "Cannot touch on a new or
    # destroyed record" ActiveStorage bug for Badge#background_image — attaching an unidentified
    # blob by its signed_id exercises TenantScopedAttachment#ensure_blob_identified the same way.
    def pending_blob(filename)
      content = "fake #{filename} bytes #{SecureRandom.hex(4)}"
      response_body = post agency_direct_uploads_path, params: {
        blob: { filename: filename, byte_size: content.bytesize, checksum: Digest::MD5.base64digest(content), content_type: "application/pdf" },
        scope: { type: "invoice_receipt", invoice_id: @invoice_id }
      }
      json = JSON.parse(response.body)
      blob = ActiveStorage::Blob.find_signed!(json["signed_id"])
      blob.upload_without_unfurling(StringIO.new(content))
      blob
    end

    it "scopes the direct-upload key under the agency's own subdomain and lets it attach as the receipt" do
      tenant = create(:account, agency: agency, name: "Acme Tenant")
      event = create_event_for(tenant, name: "Diwali Fest")
      Current.account = tenant
      invoice = create(:invoice, :awaiting_payment, event: event, account: tenant)
      @invoice_id = invoice.id

      blob = pending_blob("receipt.pdf")
      expect(blob.key).to start_with("sparkle/invoices/#{event.id}/")

      post submit_payment_agency_invoice_path(invoice), params: { utr_reference: "UTR999", receipt: blob.signed_id }

      expect(response).to redirect_to(agency_invoices_path)
      Current.account = tenant
      invoice.reload
      expect(invoice).to be_under_review
      expect(invoice.receipt).to be_attached
    end

    it "404s when the invoice belongs to a different agency" do
      other_agency = create(:agency, subdomain_slug: "other")
      other_account = create(:account, agency: other_agency)
      other_event = create_event_for(other_account)
      Current.account = other_account
      other_invoice = create(:invoice, :awaiting_payment, event: other_event, account: other_account)

      post agency_direct_uploads_path, params: {
        blob: { filename: "x.pdf", byte_size: 10, checksum: Digest::MD5.base64digest("x"), content_type: "application/pdf" },
        scope: { type: "invoice_receipt", invoice_id: other_invoice.id }
      }

      expect(response).to have_http_status(:not_found)
    end
  end
end

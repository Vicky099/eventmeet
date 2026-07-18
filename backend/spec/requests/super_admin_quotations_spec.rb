require "rails_helper"

# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6).
RSpec.describe "Platform Console quotations", type: :request do
  include ActiveJob::TestHelper

  let!(:staff) { create(:user, :platform_staff) }
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "example.com" }

  describe "GET /platform/quotations" do
    before { sign_in staff, scope: :platform_staff }

    it "lists every quotation, including already-approved ones (\"All quotations with approved and awaiting\")" do
      Current.account = account
      tenant_user = create(:user)
      needs_amount = create(:quotation, account: account, requested_by: tenant_user, event_name: "Needs Amount")
      approved = create(:quotation, :approved, account: account, requested_by: tenant_user, event_name: "Already Approved")

      get platform_quotations_path

      expect(response.body).to include("Needs Amount")
      expect(response.body).to include("Already Approved")
      expect(needs_amount).to be_pending
      expect(approved).to be_approved
    end
  end

  describe "GET /platform/quotations/:id (show)" do
    before { sign_in staff, scope: :platform_staff }

    it "shows the intake details so the Super Admin isn't pricing blind" do
      Current.account = account
      quotation = create(:quotation, account: account, requested_by: create(:user),
        expected_participant_count: 400, invite_via_email: true, invite_via_whatsapp: false, support_requested: false,
        additional_notes: "Need a stage backdrop.")

      get platform_quotation_path(quotation)

      expect(response.body).to include("400")
      expect(response.body).to include("Email")
      expect(response.body).not_to include("Email + WhatsApp")
      expect(response.body).to include("Need a stage backdrop.")
    end

    it "shows the consumed event's own name/description/dates once the quotation has been used" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation, name: "Annual Summit", description: "Our flagship event")

      get platform_quotation_path(quotation)

      expect(response.body).to include("Annual Summit")
      expect(response.body).to include("Our flagship event")
      expect(response.body).to include(event.starts_at.to_fs(:long))
      expect(response.body).to include(event.ends_at.to_fs(:long))
    end
  end

  describe "POST /platform/quotations/:id/send_amount" do
    before { sign_in staff, scope: :platform_staff }

    it "sends the amount, notifying the tenant owner" do
      Current.account = account
      tenant_user = create(:user)
      quotation = create(:quotation, account: account, requested_by: tenant_user, event_name: "Send Amount Check")
      owner = create(:user, email: "owner@acme.example", contact_num: "+15550100")
      create(:account_membership, user: owner, account: account, role: :owner)

      perform_enqueued_jobs do
        post send_amount_platform_quotation_path(quotation), params: { amount: "30000", currency: "USD" }
      end

      Current.account = account
      quotation.reload
      expect(quotation.current_amount).to eq(30_000)
      expect(quotation.currency).to eq("USD")
      expect(quotation).to be_pending
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "owner@acme.example" ])
    end

    it "rejects a blank or non-positive amount" do
      Current.account = account
      quotation = create(:quotation, account: account, requested_by: create(:user))

      post send_amount_platform_quotation_path(quotation), params: { amount: "0", currency: "INR" }

      Current.account = account
      expect(quotation.reload.current_amount).to be_nil
    end

    it "rejects an unsupported currency" do
      Current.account = account
      quotation = create(:quotation, account: account, requested_by: create(:user))

      post send_amount_platform_quotation_path(quotation), params: { amount: "30000", currency: "XYZ" }

      Current.account = account
      expect(quotation.reload.current_amount).to be_nil
    end
  end

  describe "POST /platform/quotations/:id/create_invoice" do
    before { sign_in staff, scope: :platform_staff }

    it "creates a draft invoice for the consumed event and redirects to it" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation)

      post create_invoice_platform_quotation_path(quotation)

      Current.account = account
      invoice = event.reload.invoice
      expect(invoice).to be_present
      expect(invoice).to be_draft
      expect(invoice.amount).to eq(quotation.current_amount)
      expect(response).to redirect_to(platform_invoice_path(invoice))
    end

    it "doesn't create a second invoice if one already exists (same guard as InvoiceGenerationJob)" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation)
      existing_invoice = create(:invoice, event: event, account: account)

      expect {
        post create_invoice_platform_quotation_path(quotation)
      }.not_to change { Invoice.unscoped_across_tenants { Invoice.count } }

      expect(response).to redirect_to(platform_invoice_path(existing_invoice))
    end

    it "refuses when the quotation hasn't been used to create an event yet" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))

      post create_invoice_platform_quotation_path(quotation)

      expect(response).to redirect_to(platform_quotation_path(quotation))
    end
  end

  describe "GET /platform/quotations/:id (show) — Invoice card" do
    before { sign_in staff, scope: :platform_staff }

    it "offers Create Invoice once the event exists and has none yet" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      create(:event, account: account, quotation: quotation)

      get platform_quotation_path(quotation)

      expect(response.body).to include("Create Invoice")
    end

    it "flags a still-draft invoice distinctly — it hasn't been sent to the tenant yet" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation)
      invoice = create(:invoice, event: event, account: account)

      get platform_quotation_path(quotation)

      expect(response.body).not_to include("Create Invoice")
      expect(response.body).to include("Review &amp; Send Invoice")
      expect(response.body).to include(platform_invoice_path(invoice))
    end

    it "shows a plain link to the invoice once it's actually been sent" do
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation)
      invoice = create(:invoice, :awaiting_payment, event: event, account: account)

      get platform_quotation_path(quotation)

      expect(response.body).not_to include("Create Invoice")
      expect(response.body).not_to include("Review &amp; Send Invoice")
      expect(response.body).to include(platform_invoice_path(invoice))
    end
  end
end

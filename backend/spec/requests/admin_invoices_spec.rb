require "rails_helper"

# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
# user).
RSpec.describe "Admin Console invoices", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  def create_invoice(**attrs)
    Current.account = account
    event = create(:event, account: account)
    create(:invoice, :awaiting_payment, event: event, account: account, **attrs)
  end

  describe "GET /admin/invoices" do
    it "lists this account's own invoices" do
      sign_in_with_role(:owner)
      invoice = create_invoice

      get admin_invoices_path

      expect(response.body).to include(invoice.event.name)
    end

    it "excludes drafts — those haven't been sent by the Super Admin yet" do
      sign_in_with_role(:owner)
      Current.account = account
      event = create(:event, account: account, name: "Still Draft Event")
      create(:invoice, event: event, account: account)

      get admin_invoices_path

      expect(response.body).not_to include("Still Draft Event")
    end
  end

  describe "GET /admin/invoices/:id (show)" do
    it "refuses a draft invoice — hasn't been sent yet" do
      sign_in_with_role(:owner)
      Current.account = account
      event = create(:event, account: account)
      invoice = create(:invoice, event: event, account: account)

      get admin_invoice_path(invoice)

      expect(response).to redirect_to(admin_invoices_path)
    end
  end

  describe "POST /admin/invoices/:id/submit_payment" do
    it "attaches the receipt, records the UTR, and moves the invoice under_review" do
      user = sign_in_with_role(:owner)
      invoice = create_invoice

      post submit_payment_admin_invoice_path(invoice), params: {
        utr_reference: "UTR12345",
        receipt: Rack::Test::UploadedFile.new(StringIO.new("fake receipt"), "image/png", original_filename: "receipt.png")
      }

      Current.account = account
      invoice.reload
      expect(invoice.utr_reference).to eq("UTR12345")
      expect(invoice.submitted_by).to eq(user)
      expect(invoice.receipt).to be_attached
      expect(invoice).to be_under_review
      expect(response).to redirect_to(admin_invoices_path)
    end

    it "refuses to submit without a UTR" do
      sign_in_with_role(:owner)
      invoice = create_invoice

      post submit_payment_admin_invoice_path(invoice), params: { utr_reference: "" }

      expect(invoice.reload).to be_awaiting_payment
      expect(response).to redirect_to(admin_invoices_path)
    end

    it "requires owner/event_manager" do
      sign_in_with_role(:checkin_staff)
      invoice = create_invoice

      post submit_payment_admin_invoice_path(invoice), params: { utr_reference: "UTR12345" }

      expect(response).to redirect_to(user_root_path)
    end
  end
end

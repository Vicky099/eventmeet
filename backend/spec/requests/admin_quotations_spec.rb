require "rails_helper"

# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6).
RSpec.describe "Admin Console quotations", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  describe "POST /admin/quotations" do
    it "creates a pending quotation with no amount yet, requested by the current user, capturing the intake details" do
      user = sign_in_with_role(:owner)

      post admin_quotations_path, params: {
        quotation: {
          event_name: "Annual Summit", expected_participant_count: 250,
          invite_via_email: "1", invite_via_whatsapp: "1", support_requested: "1",
          additional_notes: "Need a stage backdrop with sponsor logos."
        }
      }

      Current.account = account
      quotation = account.quotations.sole
      expect(quotation.event_name).to eq("Annual Summit")
      expect(quotation.requested_by).to eq(user)
      expect(quotation.current_amount).to be_nil
      expect(quotation).to be_pending
      expect(quotation.expected_participant_count).to eq(250)
      expect(quotation.invite_via_email).to eq(true)
      expect(quotation.invite_via_whatsapp).to eq(true)
      expect(quotation.support_requested).to eq(true)
      expect(quotation.additional_notes).to eq("Need a stage backdrop with sponsor logos.")
      expect(response).to redirect_to(admin_quotations_path)
    end

    it "requires expected_participant_count" do
      sign_in_with_role(:owner)

      expect {
        post admin_quotations_path, params: { quotation: { event_name: "Annual Summit" } }
      }.not_to change { Quotation.unscoped_across_tenants { Quotation.count } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires owner/event_manager" do
      sign_in_with_role(:checkin_staff)

      post admin_quotations_path, params: { quotation: { event_name: "Annual Summit", expected_participant_count: 100 } }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "POST /admin/quotations/:id/approve" do
    it "approves the quotation, recording who approved it, and redirects straight to New Event, prefilled" do
      user = sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, :sent, account: account, requested_by: user)

      post approve_admin_quotation_path(quotation)

      Current.account = account
      quotation.reload
      expect(quotation).to be_approved
      expect(quotation.approved_by).to eq(user)
      expect(response).to redirect_to(new_admin_event_path(quotation_id: quotation.id))
    end
  end

  describe "GET /admin/quotations (index)" do
    it "offers a Create Event action for an approved, not-yet-consumed quotation" do
      sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user), event_name: "Ready to Build")

      get admin_quotations_path

      expect(response.body).to include("Create Event")
      expect(response.body).to include(new_admin_event_path(quotation_id: quotation.id))
    end

    it "hides the Create Event action once the quotation has been consumed by an event" do
      sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      create(:event, account: account, quotation: quotation)

      get admin_quotations_path

      expect(response.body).not_to include("Create Event")
    end
  end

  describe "GET /admin/quotations/:id (show)" do
    it "shows the intake details the Super Admin needs to price it" do
      sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, account: account, requested_by: create(:user),
        expected_participant_count: 400, invite_via_email: true, invite_via_whatsapp: true, support_requested: true,
        additional_notes: "Need a stage backdrop.")

      get admin_quotation_path(quotation)

      expect(response.body).to include("400")
      expect(response.body).to include("Email + WhatsApp")
      expect(response.body).to include("Requested")
      expect(response.body).to include("Need a stage backdrop.")
    end

    it "shows the consumed event's own name/description/dates once the quotation has been used" do
      sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user))
      event = create(:event, account: account, quotation: quotation, name: "Annual Summit", description: "Our flagship event")

      get admin_quotation_path(quotation)

      expect(response.body).to include("Annual Summit")
      expect(response.body).to include("Our flagship event")
      expect(response.body).to include(event.starts_at.to_fs(:long))
      expect(response.body).to include(event.ends_at.to_fs(:long))
    end
  end

  describe "POST /admin/quotations/:id/reject" do
    it "logs a revision and requires a note" do
      user = sign_in_with_role(:owner)
      Current.account = account
      quotation = create(:quotation, :sent, account: account, requested_by: user)

      post reject_admin_quotation_path(quotation), params: { rejection_note: "" }
      Current.account = account
      expect(quotation.reload).to be_pending

      post reject_admin_quotation_path(quotation), params: { rejection_note: "Too expensive" }
      Current.account = account
      expect(quotation.reload).to be_rejected
      expect(quotation.quotation_revisions.sole.rejection_note).to eq("Too expensive")
    end
  end
end

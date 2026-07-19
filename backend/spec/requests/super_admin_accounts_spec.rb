require "rails_helper"

# Phase 2 — Tenant Oversight (Platform Console), requirement.md §4.1, §4.3, §4.7. Fixed-hierarchy
# pivot (requirement.md revisit): provisioning itself moved to AgencyConsole::AccountsController
# (spec/requests/agency_accounts_spec.rb). requirement.md revisit: "this page and sidebar link is
# not required as we have a agency to handle the tenant accounts" — the standalone list/view/edit
# surface this used to cover is gone entirely; a tenant's own details now render as a modal on its
# owning Agency's own show page (spec/requests/super_admin_agencies_spec.rb has that coverage).
# All that's left on the Platform Console's own side is suspend/reinstate, tested here as the
# plain actions they now are.
RSpec.describe "Platform Console tenant oversight", type: :request do
  let!(:staff) { create(:user, :platform_staff) }

  before { host! "example.com" }

  describe "access control" do
    it "redirects a signed-out request to sign in" do
      account = create(:account)
      patch suspend_platform_account_path(account)
      expect(response).to redirect_to(new_platform_staff_session_path)
    end
  end

  describe "PATCH /platform/accounts/:id/suspend and /reinstate" do
    let!(:account) { create(:account, subdomain_slug: "acme") }
    let!(:tenant_admin) { create(:user, email: "owner@acme.example", password: "password123!") }

    before do
      create(:account_membership, user: tenant_admin, account: account, role: :event_admin)
      sign_in staff, scope: :platform_staff
    end

    it "suspending an Account blocks its admin from logging in on their subdomain, and redirects back to the owning agency" do
      patch suspend_platform_account_path(account)

      expect(response).to redirect_to(platform_agency_path(account.agency))
      expect(account.reload).to be_suspended

      host! "acme.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      follow_redirect!
      expect(response.body).to include("Invalid email or password")

      # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md).
      entry = AuditLogEntry.sole
      expect(entry.actor).to eq(staff)
      expect(entry.action).to eq("account.suspend")
      expect(entry.target).to eq(account)
    end

    it "reinstating a suspended Account lets its admin log in again" do
      account.update!(status: :suspended)

      patch reinstate_platform_account_path(account)
      expect(account.reload).to be_active
      expect(AuditLogEntry.sole.action).to eq("account.reinstate")

      host! "acme.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      expect(response).to redirect_to("http://acme.example.com/admin")
    end

    it "redirects to the agencies list for a legacy standalone account with no agency" do
      account.update!(agency: nil)

      patch suspend_platform_account_path(account)

      expect(response).to redirect_to(platform_agencies_path)
    end
  end

  describe "removed routes" do
    it "no longer routes GET /platform/accounts at all" do
      sign_in staff, scope: :platform_staff
      get "/platform/accounts"
      expect(response).to have_http_status(:not_found)
    end
  end
end

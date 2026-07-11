require "rails_helper"

# Phase 2 — Tenant Provisioning (Platform Console), requirement.md §4.1, §4.3, §4.7.
# Companion to spec/services/account_provisioning_spec.rb, which covers the transaction/rollback
# logic this controller sits in front of.
RSpec.describe "Platform Console tenant provisioning", type: :request do
  include ActiveJob::TestHelper

  let!(:staff) { create(:user, :platform_staff) }

  before { host! "example.com" }

  describe "access control" do
    it "redirects a signed-out request to the Platform Console login" do
      get platform_accounts_path
      expect(response).to redirect_to(new_platform_staff_session_path)
    end
  end

  describe "GET /platform/accounts/new" do
    it "renders the provisioning form" do
      sign_in staff, scope: :platform_staff
      get new_platform_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Provision Account")
    end
  end

  describe "GET /platform/accounts/:id" do
    it "renders the account's details, including its breadcrumb, edit link, and no separate back-to-tenants button" do
      account = create(:account, name: "Acme Events")
      sign_in staff, scope: :platform_staff

      get platform_account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Events")
      expect(response.body).to include("breadcrumb")
      expect(response.body).to include(edit_platform_account_path(account))
      expect(response.body).not_to include("Back to Tenants")
    end
  end

  describe "POST /platform/accounts" do
    before { sign_in staff, scope: :platform_staff }

    it "creates the Account, its owner AccountMembership, initial User, and Doorkeeper::Application, all associated, and sends a welcome email" do
      slug = "acme-#{SecureRandom.hex(3)}"

      expect {
        perform_enqueued_jobs do
          post platform_accounts_path, params: {
            account: { name: "Acme Events", subdomain_slug: slug, admin_email: "owner@acme.example" }
          }
        end
      }.to change(Account, :count).by(1).and change(User, :count).by(1).and change(AccountMembership, :count).by(1)
        .and change(Doorkeeper::Application, :count).by(1)

      account = Account.find_by!(subdomain_slug: slug)
      expect(response).to redirect_to(platform_account_path(account))

      membership = account.account_memberships.sole
      expect(membership.user.email).to eq("owner@acme.example")
      expect(membership).to be_owner
      expect(membership.user.must_reset_password).to be true

      expect(account.oauth_application).to be_present
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "owner@acme.example" ])
    end

    it "rejects a reserved-word slug with a clear validation error and creates nothing" do
      expect {
        post platform_accounts_path, params: {
          account: { name: "Acme Events", subdomain_slug: "www", admin_email: "owner@acme.example" }
        }
      }.not_to change(Account, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("reserved")
    end

    it "rejects a duplicate slug with a clear validation error and creates nothing" do
      create(:account, subdomain_slug: "taken")

      expect {
        post platform_accounts_path, params: {
          account: { name: "Acme Events", subdomain_slug: "taken", admin_email: "owner@acme.example" }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already been taken")
    end
  end

  describe "GET /platform/accounts/check_slug" do
    before { sign_in staff, scope: :platform_staff }

    it "flags a reserved word" do
      get check_slug_platform_accounts_path, params: { subdomain_slug: "admin" }
      expect(response.body).to include("reserved word")
    end

    it "flags a slug that's already taken" do
      create(:account, subdomain_slug: "acme")
      get check_slug_platform_accounts_path, params: { subdomain_slug: "acme" }
      expect(response.body).to include("already taken")
    end

    it "confirms an available slug" do
      get check_slug_platform_accounts_path, params: { subdomain_slug: "brand-new-co" }
      expect(response.body).to include("available")
    end

    it "flags a syntactically invalid slug" do
      get check_slug_platform_accounts_path, params: { subdomain_slug: "no_underscores!" }
      expect(response.body).to include("lowercase")
    end

    it "does not flag a persisted account's own unchanged slug as taken, given exclude_id" do
      account = create(:account, subdomain_slug: "acme")
      get check_slug_platform_accounts_path, params: { subdomain_slug: "acme", exclude_id: account.id }
      expect(response.body).to include("available")
    end
  end

  describe "GET /platform/accounts/:id/edit" do
    it "renders the edit form, prefilled" do
      account = create(:account, name: "Acme Events", subdomain_slug: "acme")
      sign_in staff, scope: :platform_staff

      get edit_platform_account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Save Changes")
      expect(response.body).to include("Acme Events")
    end
  end

  describe "PATCH /platform/accounts/:id" do
    let!(:account) { create(:account, name: "Acme Events", subdomain_slug: "acme") }

    before { sign_in staff, scope: :platform_staff }

    it "updates the account's name and subdomain" do
      patch platform_account_path(account), params: { account: { name: "Acme Events Inc", subdomain_slug: "acme-events" } }

      expect(response).to redirect_to(platform_account_path(account))
      account.reload
      expect(account.name).to eq("Acme Events Inc")
      expect(account.subdomain_slug).to eq("acme-events")
    end

    it "rejects a reserved-word slug with a clear validation error and changes nothing" do
      patch platform_account_path(account), params: { account: { name: "Acme Events", subdomain_slug: "www" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("reserved")
      expect(account.reload.subdomain_slug).to eq("acme")
    end

    it "ignores an admin_email param — editing never creates or changes a User" do
      expect {
        patch platform_account_path(account), params: { account: { name: account.name, subdomain_slug: account.subdomain_slug, admin_email: "sneaky@example.com" } }
      }.not_to change(User, :count)
    end
  end

  describe "suspend/reinstate" do
    let!(:account) { create(:account, subdomain_slug: "acme") }
    let!(:tenant_admin) { create(:user, email: "owner@acme.example", password: "password123!") }

    before do
      create(:account_membership, user: tenant_admin, account: account, role: :owner)
      sign_in staff, scope: :platform_staff
    end

    it "suspending an Account blocks its admin from logging in on their subdomain (ties back to Phase 1)" do
      patch suspend_platform_account_path(account)
      expect(response).to redirect_to(platform_account_path(account))
      expect(account.reload).to be_suspended

      host! "acme.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      follow_redirect!
      expect(response.body).to include("Invalid email or password")
    end

    it "reinstating a suspended Account lets its admin log in again" do
      account.update!(status: :suspended)

      patch reinstate_platform_account_path(account)
      expect(account.reload).to be_active

      host! "acme.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      expect(response).to redirect_to("http://acme.example.com/admin")
    end
  end

  describe "GET /platform/accounts" do
    before { sign_in staff, scope: :platform_staff }

    it "searches by name/subdomain and filters by status" do
      active = create(:account, name: "Acme Events", subdomain_slug: "acme-search")
      suspended = create(:account, name: "Other Co", subdomain_slug: "othersusp", status: :suspended)

      get platform_accounts_path, params: { q: "acme" }
      expect(response.body).to include(active.name)
      expect(response.body).not_to include(suspended.name)

      get platform_accounts_path, params: { status: "suspended" }
      expect(response.body).to include(suspended.name)
      expect(response.body).not_to include(active.name)
    end
  end
end

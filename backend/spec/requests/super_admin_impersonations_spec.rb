require "rails_helper"

# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md).
# SuperAdmin::ImpersonationsController#create mints the token on the apex domain;
# Admin::ImpersonationsController#redeem/#destroy consume it and end it on the tenant's own
# subdomain. Mirrors spec/requests/agency_account_switch_spec.rb's own shape closely — same
# mint-then-redeem cross-subdomain flow, just Super-Admin-initiated instead of self-serve.
RSpec.describe "Super Admin impersonation", type: :request do
  let!(:staff) { create(:user, :platform_staff) }
  let!(:account) { create(:account, subdomain_slug: "acme-tenant") }
  let!(:tenant_user) { create(:user, email: "admin@acme.example", password: "password123!") }

  before do
    create(:account_membership, user: tenant_user, account: account, role: :event_admin)
  end

  def initiate_impersonation
    host! "example.com"
    sign_in staff, scope: :platform_staff
    post platform_account_impersonations_path(account), params: { user_id: tenant_user.id }
  end

  it "mints a fresh ImpersonationToken, redirects to the tenant's own subdomain, and logs the start against the real Super Admin" do
    expect { initiate_impersonation }.to change(ImpersonationToken, :count).by(1).and change(AuditLogEntry, :count).by(1)

    token = ImpersonationToken.last
    expect(token.platform_staff).to eq(staff)
    expect(token.user).to eq(tenant_user)
    expect(token.account).to eq(account)
    expect(response).to redirect_to("http://acme-tenant.example.com/admin/impersonate?token=#{token.token}")

    entry = AuditLogEntry.last
    expect(entry.actor).to eq(staff)
    expect(entry.action).to eq("impersonation.start")
    expect(entry.target).to eq(account)
    expect(entry.metadata).to eq("impersonated_user_email" => tenant_user.email)
  end

  it "redeeming signs the Super Admin in as the impersonated user and shows the banner, with no second login" do
    initiate_impersonation
    token = ImpersonationToken.last

    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    expect(response).to redirect_to(user_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Impersonating #{tenant_user.email}")
    expect(response.body).to include(staff.email)

    get user_root_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks a second redemption of the same token" do
    initiate_impersonation
    token = ImpersonationToken.last
    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    delete destroy_user_session_path # sign back out to prove the second hit doesn't ride the first sign-in
    get redeem_impersonation_path(token: token.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("expired or already been used")
  end

  it "rejects an expired token" do
    token = create(:impersonation_token, platform_staff: staff, user: tenant_user, account: account, expires_at: 1.second.ago)

    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("expired or already been used")
  end

  it "rejects redemption if the AccountMembership was removed after the token was minted" do
    initiate_impersonation
    token = ImpersonationToken.last
    AccountMembership.find_by!(user: tenant_user, account: account).destroy!

    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("no longer has access")
  end

  # The one check worth getting right above every other in this file (doc/implementation_3.md's
  # own DoD wording) — getting this backwards defeats the entire feature.
  it "attributes a state-changing action taken while impersonating to the real Super Admin, not the impersonated user" do
    initiate_impersonation
    token = ImpersonationToken.last
    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    Current.account = account
    event = create(:event, account: account, name: "Original Name")
    Current.account = nil

    expect {
      patch admin_event_path(event), params: { event: { name: "Renamed by impersonator" } }
    }.to change(AuditLogEntry, :count).by(1)

    entry = AuditLogEntry.last
    expect(entry.actor).to eq(staff)
    expect(entry.action).to eq("impersonation.events#update")
    expect(entry.target).to eq(tenant_user)
    expect(entry.metadata["impersonated_user_email"]).to eq(tenant_user.email)
  end

  it "does not audit a plain GET made while impersonating (only state-changing requests)" do
    initiate_impersonation
    token = ImpersonationToken.last
    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    expect {
      get user_root_path
    }.not_to change(AuditLogEntry, :count)
  end

  it "stopping impersonation clears the session and returns to the Platform Console with no re-login" do
    initiate_impersonation
    token = ImpersonationToken.last
    host! "acme-tenant.example.com"
    get redeem_impersonation_path(token: token.token)

    delete stop_impersonation_path

    expect(response).to redirect_to("http://example.com/platform")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Impersonating")
  end
end

require "rails_helper"

# Agency → Tenant account switch (requirement.md revisit: "agency will controlled all the event
# using single sign-in as switch account") — AgencyConsole::AccountsController#switch mints the
# token on the agency subdomain; Admin::AccountSwitchesController#redeem consumes it on the
# tenant's own subdomain. Companion to spec/models/account_switch_spec.rb, which covers the token
# model's own lifecycle in isolation.
RSpec.describe "Agency to tenant account switch", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "sparkle") }
  let!(:agency_admin) { create(:user, email: "admin@sparkle.example", password: "password123!") }
  let!(:account) { create(:account, agency: agency, subdomain_slug: "acme-tenant") }

  before do
    create(:agency_membership, user: agency_admin, agency: agency)
    # Mirrors what AccountProvisioning actually grants every existing agency staff member the
    # moment a tenant is created — the AccountMembership the switch's own authorization ultimately
    # relies on (User#authorized_for_current_host?).
    create(:account_membership, user: agency_admin, account: account, role: :event_admin)
  end

  def initiate_switch
    host! "sparkle.example.com"
    sign_in agency_admin, scope: :user
    post switch_agency_account_path(account)
  end

  it "redirects to the tenant's own subdomain, carrying a fresh AccountSwitch token" do
    expect { initiate_switch }.to change(AccountSwitch, :count).by(1)

    switch = AccountSwitch.last
    expect(switch.user).to eq(agency_admin)
    expect(switch.account).to eq(account)
    expect(response).to redirect_to("http://acme-tenant.example.com/admin/switch?token=#{switch.token}")
  end

  it "redeeming signs the agency admin in on the tenant subdomain with no second login" do
    initiate_switch
    switch = AccountSwitch.last

    host! "acme-tenant.example.com"
    get redeem_account_switch_path(token: switch.token)

    expect(response).to redirect_to(user_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Switched to #{account.name}")

    # Actually signed in, not just redirected — a follow-up request to a protected page succeeds
    # with no redirect back to the login form.
    get user_root_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks a second redemption of the same token" do
    initiate_switch
    switch = AccountSwitch.last
    host! "acme-tenant.example.com"
    get redeem_account_switch_path(token: switch.token)

    delete destroy_user_session_path # sign back out to prove the second hit doesn't ride the first sign-in
    get redeem_account_switch_path(token: switch.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("expired or already been used")
  end

  it "rejects an expired token" do
    switch = create(:account_switch, user: agency_admin, account: account, expires_at: 1.second.ago)

    host! "acme-tenant.example.com"
    get redeem_account_switch_path(token: switch.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("expired or already been used")
  end

  it "rejects switching into a tenant that belongs to a different agency" do
    other_agency = create(:agency, subdomain_slug: "other-agency")
    other_account = create(:account, agency: other_agency, subdomain_slug: "other-tenant")

    host! "sparkle.example.com"
    sign_in agency_admin, scope: :user
    post switch_agency_account_path(other_account)

    expect(response).to have_http_status(:not_found)
  end

  it "rejects redemption if the AccountMembership was removed after the token was minted" do
    initiate_switch
    switch = AccountSwitch.last
    AccountMembership.find_by!(user: agency_admin, account: account).destroy!

    host! "acme-tenant.example.com"
    get redeem_account_switch_path(token: switch.token)

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("no longer have access")
  end
end

require "rails_helper"

# requirement.md revisit: "show only latest 10 tenants and top right corner of tenant will have
# view all link and also have a sidebar which will have all the tenants with pagination." —
# AgencyConsole::AccountsController#index, the full paginated tenant list behind the dashboard's
# own "View all" link (spec/requests/agency_console_dashboard_spec.rb has that link's own
# coverage) and its own sidebar entry (AgencyHelper#agency_nav_items).
RSpec.describe "Agency Console tenant list", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "acme-agency") }
  let!(:agency_user) { create(:user) }

  before do
    create(:agency_membership, user: agency_user, agency: agency)
    host! "acme-agency.example.com"
    sign_in agency_user, scope: :user
  end

  describe "access control" do
    it "redirects a signed-out request to sign in" do
      sign_out agency_user

      get agency_accounts_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  it "renders with no tenants yet" do
    get agency_accounts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No tenants yet")
  end

  it "shows each tenant's own event/participant counts, isolated per tenant" do
    account_a = create(:account, agency: agency, name: "Tenant A")
    account_b = create(:account, agency: agency, name: "Tenant B")

    Current.account = account_a
    event_a = create(:event, account: account_a, name: "Only In A")
    create(:participant, account: account_a, event: event_a)
    create(:participant, account: account_a, event: event_a)
    Current.account = account_b
    create(:event, account: account_b, name: "Only In B")
    Current.account = nil

    get agency_accounts_path

    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body).css("table tbody tr")
    row_a = rows.find { |row| row.text.include?("Tenant A") }
    row_b = rows.find { |row| row.text.include?("Tenant B") }

    expect(row_a.css("td").map(&:text)[2].strip).to eq("1") # Events
    expect(row_a.css("td").map(&:text)[3].strip).to eq("2") # Participants
    expect(row_b.css("td").map(&:text)[2].strip).to eq("1") # Events
    expect(row_b.css("td").map(&:text)[3].strip).to eq("0") # Participants
  end

  it "paginates at 15 per page and never shows another agency's own tenants" do
    create_list(:account, 16, agency: agency)
    other_agency = create(:agency, subdomain_slug: "other-agency")
    other_account = create(:account, agency: other_agency, name: "Other Agency's Tenant")

    get agency_accounts_path

    rows = Nokogiri::HTML(response.body).css("table tbody tr")
    expect(rows.size).to eq(15)
    expect(response.body).not_to include(other_account.name)

    get agency_accounts_path, params: { page: 2 }

    rows = Nokogiri::HTML(response.body).css("table tbody tr")
    expect(rows.size).to eq(1)
  end

  # requirement.md revisit: "have a action to suspend and reinstate" — the agency's own oversight
  # of its own tenants, mirrors spec/requests/super_admin_accounts_spec.rb's own coverage one tier
  # down, `Current.agency.accounts.find` as the authorization boundary instead of a bare `Account.find`.
  describe "PATCH /agency/accounts/:id/suspend and /reinstate" do
    let!(:account) { create(:account, agency: agency, subdomain_slug: "acme-tenant") }
    let!(:tenant_admin) { create(:user, email: "owner@acme-tenant.example", password: "password123!") }

    before { create(:account_membership, user: tenant_admin, account: account, role: :event_admin) }

    it "suspending an Account blocks its admin from logging in on their subdomain" do
      patch suspend_agency_account_path(account)

      expect(response).to redirect_to(agency_accounts_path)
      expect(account.reload).to be_suspended

      host! "acme-tenant.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      follow_redirect!
      expect(response.body).to include("Invalid email or password")
    end

    it "reinstating a suspended Account lets its admin log in again" do
      account.update!(status: :suspended)

      patch reinstate_agency_account_path(account)
      expect(account.reload).to be_active

      host! "acme-tenant.example.com"
      post user_session_path, params: { user: { email: tenant_admin.email, password: "password123!" } }
      expect(response).to redirect_to("http://acme-tenant.example.com/admin")
    end

    it "404s trying to suspend another agency's own tenant" do
      other_agency = create(:agency, subdomain_slug: "other-agency")
      other_account = create(:account, agency: other_agency)

      patch suspend_agency_account_path(other_account)

      expect(response).to have_http_status(:not_found)
      expect(other_account.reload).to be_active
    end
  end
end

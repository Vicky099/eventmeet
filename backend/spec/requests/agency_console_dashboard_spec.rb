require "rails_helper"

# Fixed-hierarchy pivot (requirement.md revisit): AgencyConsole::DashboardController#index —
# the agency's own tenant + event listing, plus (requirement.md revisit: "design the agency
# analytics dashboard") its own at-a-glance stats, payment action queue, and live pulse.
#
# Regression: listing events across more than one of an agency's own tenant Accounts is a
# deliberate cross-tenant read from a single Current.account's own point of view (there is no
# Current.account at all on an agency subdomain, only Current.agency) — TenantScoped's
# default_scope doesn't recognize that third context and raises MissingTenantContextError unless
# the controller explicitly opens it via .unscoped_across_tenants (found live: the dashboard 500'd
# the moment a tenant with any events existed under an agency). The same gap applies to the new
# Invoices Needing Payment section's own :event preload — covered below too.
RSpec.describe "Agency Console dashboard", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "acme-agency") }
  let!(:agency_user) { create(:user) }

  before do
    create(:agency_membership, user: agency_user, agency: agency)
    host! "acme-agency.example.com"
    sign_in agency_user, scope: :user
  end

  it "renders with no tenants yet" do
    get agency_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No tenants yet")
  end

  it "renders each tenant's own event/participant counts without raising TenantScoped::MissingTenantContextError" do
    account = create(:account, agency: agency, name: "Acme Sub Events")
    Current.account = account
    event = create(:event, account: account, name: "Diwali Fest")
    create(:participant, account: account, event: event)
    Current.account = nil

    get agency_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acme Sub Events")
  end

  it "keeps one tenant's event/participant counts out of another tenant's own row" do
    account_a = create(:account, agency: agency, name: "Tenant A")
    account_b = create(:account, agency: agency, name: "Tenant B")

    Current.account = account_a
    event_a = create(:event, account: account_a, name: "Only In A")
    create(:participant, account: account_a, event: event_a)
    create(:participant, account: account_a, event: event_a)
    Current.account = account_b
    create(:event, account: account_b, name: "Only In B")
    Current.account = nil

    get agency_root_path

    expect(response).to have_http_status(:ok)

    # Both tenants get exactly one event each; Tenant A additionally has 2 participants, Tenant B
    # none — the real regression this guards is per-account isolation (a count leaking across
    # tenants), read straight off each tenant's own table row rather than the raw event/
    # participant names (the dashboard shows aggregate counts per tenant, not a per-event list).
    rows = Nokogiri::HTML(response.body).css("table tbody tr")
    row_a = rows.find { |row| row.text.include?("Tenant A") }
    row_b = rows.find { |row| row.text.include?("Tenant B") }
    cells_a = row_a.css("td").map(&:text)
    cells_b = row_b.css("td").map(&:text)

    expect(cells_a[2].strip).to eq("1") # Events
    expect(cells_a[3].strip).to eq("2") # Participants
    expect(cells_b[2].strip).to eq("1") # Events
    expect(cells_b[3].strip).to eq("0") # Participants
  end

  it "shows Total Paid/Outstanding and an awaiting_payment invoice as a payable action item, without raising MissingTenantContextError on the :event preload" do
    account = create(:account, agency: agency, name: "Acme Sub Events")
    Current.account = account
    event = create(:event, account: account, status: :completed, name: "Diwali Fest")
    create(:invoice, :paid, event: event, account: account, amount: 12_000)
    review_event = create(:event, account: account, status: :completed, name: "Under Review Fest")
    create(:invoice, :under_review, event: review_event, account: account, amount: 3_000)
    due_event = create(:event, account: account, status: :completed, name: "Due Fest")
    due_invoice = create(:invoice, :awaiting_payment, event: due_event, account: account, amount: 7_000)
    Current.account = nil

    get agency_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total Paid")
    expect(response.body).to include("12,000")
    expect(response.body).to include("Outstanding")
    # awaiting_payment (7,000) + under_review (3,000) — both outstanding, only the former is
    # actionable by the agency right now.
    expect(response.body).to include("10,000")
    expect(response.body).to include("Invoices Needing Payment")
    expect(response.body).to include("Due Fest")
    expect(response.body).to include(agency_invoice_path(due_invoice))
    expect(response.body).not_to include("Under Review Fest") # already submitted — nothing left for the agency to do
  end

  # requirement.md revisit: "show only latest 10 tenants and top right corner of tenant will
  # have view all link" — the Tenants card itself is a preview now, capped to the newest 10;
  # AgencyConsole::AccountsController#index (spec/requests/agency_console_accounts_spec.rb) is
  # the full list behind "View all".
  it "shows only the latest 10 tenants, oldest excluded, with a View all link to the full list" do
    accounts = Array.new(11) { |i| create(:account, agency: agency, name: "Tenant #{i}", created_at: i.days.ago) }
    oldest = accounts.min_by(&:created_at) # created 10.days.ago — the 11th-newest, pushed out of the top 10

    get agency_root_path

    expect(response.body).to include(agency_accounts_path)
    expect(response.body).to include(">View all<")
    expect(response.body).not_to include(oldest.name)

    # The stat row's own Tenants count still reflects all 11, not just the previewed 10.
    tenants_label = Nokogiri::HTML(response.body).css("h6").find { |h6| h6.text.strip == "Tenants" }
    expect(tenants_label.parent.at_css("h4").text).to include("11")
  end

  # requirement.md revisit: "same action here as well for tenants" — the dashboard's own Tenants
  # preview card gets the identical Suspend/Reinstate pair
  # spec/requests/agency_console_accounts_index_spec.rb's own "PATCH .../suspend and /reinstate"
  # describe block already covers on the full list page; this just confirms the same controller
  # actions are reachable and rendered from here too, and return to this page afterward.
  it "suspends and reinstates a tenant from the dashboard's own Tenants card, returning here" do
    account = create(:account, agency: agency, name: "Acme Sub Events")

    patch suspend_agency_account_path(account), headers: { "HTTP_REFERER" => agency_root_path }
    expect(response).to redirect_to(agency_root_path)
    expect(account.reload).to be_suspended

    get agency_root_path
    expect(response.body).to include("Reinstate")

    patch reinstate_agency_account_path(account), headers: { "HTTP_REFERER" => agency_root_path }
    expect(response).to redirect_to(agency_root_path)
    expect(account.reload).to be_active
  end
end

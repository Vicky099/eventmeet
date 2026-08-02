require "rails_helper"

# doc/event_page_templates_plan.md, Stage 2 — the Agency Console's own read-only drill-down into
# a tenant's events, existing solely to reach that event's Event Page screen (Stage 3). Mirrors
# spec/requests/agency_console_accounts_index_spec.rb's own cross-agency-leak pattern.
RSpec.describe "Agency Console tenant events list", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "acme-agency") }
  let!(:agency_user) { create(:user) }
  let!(:account) { create(:account, agency: agency, name: "Tenant A") }

  before do
    create(:agency_membership, user: agency_user, agency: agency)
    host! "acme-agency.example.com"
    sign_in agency_user, scope: :user
  end

  it "redirects a signed-out request to sign in" do
    sign_out agency_user

    get agency_account_events_path(account)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders with no events yet" do
    get agency_account_events_path(account)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("no events yet")
  end

  it "lists the tenant's own events with their Event Page state, isolated per event" do
    Current.account = account
    event_without_page = create(:event, account: account, name: "No Page Yet")
    event_with_custom_html = create(:event, account: account, name: "Has Custom HTML")
    create(:event_page, account: account, event: event_with_custom_html)
    event_with_template = create(:event, account: account, name: "Has A Template")
    create(:event_page, account: account, event: event_with_template, template_key: :template_2)
    Current.account = nil

    get agency_account_events_path(account)

    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body).css("table tbody tr")

    row_for = ->(name) { rows.find { |row| row.text.include?(name) } }
    expect(row_for.call(event_without_page.name).text).to include("Not set")
    expect(row_for.call(event_with_custom_html.name).text).to include("Custom HTML")
    expect(row_for.call(event_with_template.name).text).to include("Template 2")
  end

  it "404s for an account belonging to a different agency" do
    other_agency = create(:agency, subdomain_slug: "other-agency")
    other_account = create(:account, agency: other_agency, name: "Other Agency's Tenant")

    get agency_account_events_path(other_account)

    expect(response).to have_http_status(:not_found)
  end
end

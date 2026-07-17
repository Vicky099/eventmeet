require "rails_helper"

# requirement.md revisit: "once you set checkout and select session or entrance and we refresh
# the page then the selection will stay as it is." Purely client-side (checkin_controls_controller
# .js persists the Direction/Session pill/chip choice to localStorage, keyed by event id, and
# restores it on connect) — a request spec's rack-test driver has no JS/localStorage, so this can
# only actually be proven with a real browser. Same Playwright + host-resolver-rules setup
# live_dashboard_spec.rb already established for reaching a tenant subdomain from a system spec.
RSpec.describe "Check-in kiosk controls persistence", type: :system do
  before do
    Capybara.register_driver(:playwright_tenant_host) do |app|
      Capybara::Playwright::Driver.new(app,
        browser_type: :chromium,
        headless: ENV["PLAYWRIGHT_HEADFUL"].blank?,
        args: [ "--host-resolver-rules=MAP acme.example.com 127.0.0.1" ])
    end
    Capybara.current_driver = :playwright_tenant_host
    Capybara.app_host = "http://acme.example.com"
    Capybara.always_include_port = true
  end

  after do
    Capybara.use_default_driver
    Capybara.app_host = nil
    Capybara.always_include_port = false
  end

  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) do
    Current.account = account
    u = create(:user, email: "checkin@acme.example", password: "password123!")
    create(:account_membership, user: u, account: account, role: :owner)
    u
  end
  let!(:event) { Current.account = account; create(:event, account: account) }
  let!(:session_row) { Current.account = account; create(:session, account: account, event: event, name: "Keynote Hall") }

  def sign_in_via_browser
    visit "/admin/login"
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123!"
    click_button "Log In"
  end

  it "keeps the Direction/Session choice across a page refresh" do
    sign_in_via_browser
    visit "/checkin/#{event.slug}"

    click_button "Check out"
    click_button "Keynote Hall"

    visit "/checkin/#{event.slug}" # a plain re-visit of the same URL — functionally a refresh

    expect(page.find("button", text: "Check out")[:class]).to include("is-active")
    expect(page.find("button", text: "Event entrance")[:class]).not_to include("is-active")
    expect(page.find("button", text: "Keynote Hall")[:class]).to include("is-active")
  end
end

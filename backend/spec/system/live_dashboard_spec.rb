require "rails_helper"

# Phase 9 Definition of Done: "a check-in scan in one browser session updates a second connected
# browser session's dashboard tile without a page reload, under 1 second."
RSpec.describe "Live dashboard updates", type: :system do
  # The app's tenant routing is Host-header-based (Hosting::TenantSubdomainConstraint), and the
  # test env's platform_domain is "example.com" (config/initializers/multi_tenancy.rb) — a real
  # public domain, so a real headless browser can't resolve "acme.example.com" to this spec's own
  # local Capybara/Puma server the way request specs' `host!` fakes it for a fake in-process
  # client. Chromium's --host-resolver-rules launch flag remaps that hostname to 127.0.0.1 at the
  # browser-process level (no /etc/hosts edit, no external DNS dependency); Capybara's
  # always_include_port then appends the actual dynamic Puma port Capybara started, once app_host
  # is set to use that hostname.
  before do
    Capybara.register_driver(:playwright_tenant_host) do |app|
      Capybara::Playwright::Driver.new(app,
        browser_type: :chromium,
        headless: ENV["PLAYWRIGHT_HEADFUL"].blank?,
        args: [ "--host-resolver-rules=MAP acme.example.com 127.0.0.1" ])
    end
    Capybara.app_host = "http://acme.example.com"
    Capybara.always_include_port = true
  end

  after do
    Capybara.app_host = nil
    Capybara.always_include_port = false
  end

  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) do
    Current.account = account
    u = create(:user, email: "checkin@acme.example", password: "password123!")
    create(:account_membership, user: u, account: account, role: :event_admin)
    u
  end
  let!(:event) do
    Current.account = account
    create(:event, account: account, mode: :on_site, status: :live)
  end
  let!(:participant) do
    Current.account = account
    create(:participant, account: account, event: event, name: "Live Update Alice")
  end

  def sign_in_via_browser(session)
    session.visit "/admin/login"
    session.fill_in "Email", with: user.email
    session.fill_in "Password", with: "password123!"
    session.click_button "Log In"
  end

  # The "Checked In" value specifically, not just any digit on the page — registered_count is
  # already 1 (the participant created above) before any scan happens, so a bare "does the page
  # contain 1" check would be a false positive from the very first page load.
  def checked_in_value(session)
    session.find(:xpath, "//h6[normalize-space(text())='Checked In']/following-sibling::h4").text.strip
  end

  it "patches a second connected dashboard's Checked In tile when a scan happens elsewhere, with no reload" do
    session_a = Capybara::Session.new(:playwright_tenant_host, Rails.application)
    session_b = Capybara::Session.new(:playwright_tenant_host, Rails.application)

    sign_in_via_browser(session_a)
    session_a.visit "/admin/events/#{event.slug}/scan_events"
    sign_in_via_browser(session_b)
    session_b.visit "/admin/events/#{event.slug}/scan_events"

    expect(checked_in_value(session_a)).to start_with("0")
    expect(checked_in_value(session_b)).to start_with("0")

    Current.account = account
    ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, source: :kiosk)

    [ session_a, session_b ].each do |session|
      Capybara.using_session(session) do
        expect(session).to have_selector(
          :xpath, "//h6[normalize-space(text())='Checked In']/following-sibling::h4[starts-with(normalize-space(text()), '1')]",
          wait: 5
        )
      end
    end
  ensure
    session_a&.quit
    session_b&.quit
  end
end

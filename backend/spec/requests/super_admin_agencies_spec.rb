require "rails_helper"

# Agency layer (requirement.md revisit): Platform Console provisioning + management for Agency —
# mirrors spec/requests/super_admin_accounts_spec.rb's own shape one tier up.
RSpec.describe "Platform Console agency provisioning", type: :request do
  include ActiveJob::TestHelper

  let!(:staff) { create(:user, :platform_staff) }

  before { host! "example.com" }

  describe "access control" do
    it "redirects a signed-out request to the Platform Console login" do
      get platform_agencies_path
      expect(response).to redirect_to(new_platform_staff_session_path)
    end
  end

  # requirement.md revisit: "design this in proper way. show all necessary details and agency
  # level performance analytics, his tenants and his events and how much participants was there
  # in the event."
  describe "GET /platform/agencies/:id" do
    before { sign_in staff, scope: :platform_staff }

    it "shows tenant/event/participant counts, Total Paid, and each event's own participant count" do
      agency = create(:agency, name: "Sparkle Events Agency")
      account = create(:account, agency: agency, name: "Acme Tenant")
      Current.account = account
      paid_event = create(:event, account: account, status: :completed, name: "Paid Event")
      create(:invoice, :paid, event: paid_event, account: account, amount: 15_000)
      live_event = create(:event, account: account, status: :live, name: "Live Event")
      create(:participant, account: account, event: live_event)
      create(:participant, account: account, event: live_event)
      Current.account = nil

      get platform_agency_path(agency)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tenants")
      expect(response.body).to include("Acme Tenant")
      expect(response.body).to include("Events")
      expect(response.body).to include("Paid Event")
      expect(response.body).to include("Live Event")
      expect(response.body).to include("Participants")
      expect(response.body).to include("Total Paid")
      expect(response.body).to include("15,000")

      # The event-level participant count is the real regression this guards — a bare tenant
      # rollup wouldn't tell a Super Admin *which* event actually has attendees.
      rows = Nokogiri::HTML(response.body).css("table tbody tr")
      live_row = rows.find { |row| row.text.include?("Live Event") }
      expect(live_row.css("td").map(&:text).map(&:strip)).to include("2")
    end

    it "never shows another agency's tenants or events" do
      agency = create(:agency, name: "Sparkle Events Agency")
      other_agency = create(:agency, name: "Other Agency")
      other_account = create(:account, agency: other_agency, name: "Other Tenant")
      Current.account = other_account
      create(:event, account: other_account, name: "Other Event")
      Current.account = nil

      get platform_agency_path(agency)

      expect(response.body).not_to include("Other Tenant")
      expect(response.body).not_to include("Other Event")
    end

    # requirement.md revisit: "when click on tenant name then open the modal and show tenant
    # details. also when click on event name then show the event details on modal." — no
    # separate page for either anymore (super_admin/accounts's own index/show/edit are gone
    # entirely, spec/requests/super_admin_accounts_spec.rb has that removal's own coverage); both
    # render as a real Bootstrap modal, inline on this same page load.
    it "renders a details modal for each tenant and each event, not a link to a separate page" do
      agency = create(:agency, name: "Sparkle Events Agency")
      account = create(:account, agency: agency, name: "Acme Tenant", contact_email: "hello@acme.example")
      Current.account = account
      event = create(:event, account: account, status: :up_coming, name: "Diwali Fest", address: "123 Main St")
      Current.account = nil

      get platform_agency_path(agency)

      doc = Nokogiri::HTML(response.body)

      tenant_trigger = doc.at_css("button[data-bs-target='#tenant-modal-#{account.id}']")
      expect(tenant_trigger.text.strip).to eq("Acme Tenant")

      tenant_modal = doc.at_css("#tenant-modal-#{account.id}")
      expect(tenant_modal.text).to include("hello@acme.example")
      expect(tenant_modal.at_css("form[action='#{suspend_platform_account_path(account)}']")).to be_present

      event_trigger = doc.at_css("button[data-bs-target='#event-modal-#{event.id}']")
      expect(event_trigger.text.strip).to eq("Diwali Fest")

      event_modal = doc.at_css("#event-modal-#{event.id}")
      expect(event_modal.text).to include("123 Main St")
      expect(event_modal.text).to include("Acme Tenant")

      # Neither is a link to a now-removed standalone page.
      expect(response.body).not_to include("/platform/accounts/#{account.id}\"")
    end

    # requirement.md revisit: "if event has used the whatsApp messages for invitation then show
    # the messages sent via whatsApp count ... overall how much messages used by agency." The only
    # WhatsApp this app ever sends is a per-event Invoice's own invoice-sent/payment-rejected
    # notification (SuperAdmin::AgenciesController#show's own comment) — only a `sent` one counts
    # (a `failed` row never actually reached Gupshup), and only the agency's own stat sums across
    # every one of its events, not another agency's.
    it "shows an event's own WhatsApp message count on its modal, only counting sent (not failed) sends, and rolls up an agency-wide total" do
      agency = create(:agency, name: "Sparkle Events Agency")
      account = create(:account, agency: agency, name: "Acme Tenant")
      Current.account = account
      event = create(:event, account: account, name: "Diwali Fest")
      invoice = create(:invoice, :awaiting_payment, event: event, account: account)
      create_list(:notification, 2, account: account, notifiable: invoice, channel: :whatsapp, status: :sent)
      create(:notification, account: account, notifiable: invoice, channel: :whatsapp, status: :failed)
      create(:notification, account: account, notifiable: invoice, channel: :email, status: :sent)

      quiet_event = create(:event, account: account, name: "Quiet Fest") # no WhatsApp history at all
      Current.account = nil

      get platform_agency_path(agency)

      expect(response.body).to include("WhatsApp Messages")

      # Agency-wide stat: only the 2 sent whatsapp Notifications, not the failed one or the email one.
      tenants_label = Nokogiri::HTML(response.body).css("h6").find { |h6| h6.text.strip == "WhatsApp Messages" }
      expect(tenants_label.parent.at_css("h4").text.strip).to eq("2")

      event_modal = Nokogiri::HTML(response.body).at_css("#event-modal-#{event.id}")
      expect(event_modal.text).to include("WhatsApp Messages")
      dd = event_modal.css("dt").find { |dt| dt.text.strip == "WhatsApp Messages" }&.next_element
      expect(dd.text.strip).to eq("2")

      # An event with no WhatsApp history at all doesn't show the row (nothing to report, not a "0").
      quiet_modal = Nokogiri::HTML(response.body).at_css("#event-modal-#{quiet_event.id}")
      expect(quiet_modal.css("dt").map(&:text)).not_to include("WhatsApp Messages")
    end
  end

  describe "POST /platform/agencies" do
    before { sign_in staff, scope: :platform_staff }

    it "creates the Agency, its agency_admin User and AgencyMembership, and sends a welcome email" do
      expect {
        perform_enqueued_jobs do
          post platform_agencies_path, params: {
            agency: {
              name: "Acme Agency", subdomain_slug: "acme-agency", admin_email: "agency-admin@example.com",
              contact_email: "contact@agency.example", contact_num: "+1 555 0100",
              price_per_event: "10000", currency: "INR", events_granted: "5"
            }
          }
        end
      }.to change(Agency, :count).by(1).and change(User, :count).by(1).and change(AgencyMembership, :count).by(1)

      agency = Agency.find_by!(name: "Acme Agency")
      expect(response).to redirect_to(platform_agency_path(agency))

      membership = agency.agency_memberships.sole
      expect(membership.user.email).to eq("agency-admin@example.com")
      expect(membership).to be_agency_admin
      expect(membership.user.must_reset_password).to be true

      expect(ActionMailer::Base.deliveries.last.to).to eq([ "agency-admin@example.com" ])
    end

    it "re-renders with errors and creates nothing when the price is invalid" do
      expect {
        post platform_agencies_path, params: {
          agency: { name: "Acme Agency", admin_email: "agency-admin@example.com", price_per_event: "-5" }
        }
      }.not_to change(Agency, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "grant_events" do
    let!(:agency) { create(:agency, events_granted: 5, events_used: 2) }

    before { sign_in staff, scope: :platform_staff }

    it "adds to events_granted" do
      post grant_events_platform_agency_path(agency), params: { count: 3 }

      expect(agency.reload.events_granted).to eq(8)
      expect(response).to redirect_to(platform_agency_path(agency))
    end

    it "rejects a non-positive count" do
      post grant_events_platform_agency_path(agency), params: { count: 0 }

      expect(agency.reload.events_granted).to eq(5)
    end
  end

  describe "suspend/reinstate" do
    let!(:agency) { create(:agency) }

    before { sign_in staff, scope: :platform_staff }

    it "suspends and reinstates" do
      patch suspend_platform_agency_path(agency)
      expect(agency.reload).to be_suspended

      patch reinstate_platform_agency_path(agency)
      expect(agency.reload).to be_active
    end
  end

  describe "POST /platform/agencies/:agency_id/agency_memberships" do
    let!(:agency) { create(:agency) }
    let!(:tenant) { create(:account, agency: agency) }

    before { sign_in staff, scope: :platform_staff }

    it "adds a new agency_admin by email" do
      expect {
        perform_enqueued_jobs do
          post platform_agency_agency_memberships_path(agency), params: { email: "new-staff@example.com" }
        end
      }.to change(AgencyMembership, :count).by(1)

      expect(ActionMailer::Base.deliveries.last.to).to eq([ "new-staff@example.com" ])
    end

    it "gives the new agency_admin an event_admin AccountMembership on the agency's existing tenant" do
      post platform_agency_agency_memberships_path(agency), params: { email: "new-staff@example.com" }

      user = User.find_by!(email: "new-staff@example.com")
      membership = tenant.account_memberships.find_by(user: user)
      expect(membership).to be_present
      expect(membership).to be_event_admin
    end

    it "removes an agency admin without touching their existing tenant AccountMembership" do
      user = create(:user, email: "existing-staff@example.com")
      agency_membership = create(:agency_membership, user: user, agency: agency)
      create(:account_membership, user: user, account: tenant, role: :event_admin)

      expect {
        delete platform_agency_agency_membership_path(agency, agency_membership)
      }.to change(AgencyMembership, :count).by(-1)

      expect(tenant.account_memberships.exists?(user: user)).to be true
    end
  end

  describe "POST /platform/agencies/:agency_id/agency_memberships/:id/resend_invite" do
    let!(:agency) { create(:agency) }

    before { sign_in staff, scope: :platform_staff }

    it "regenerates a temp password and re-sends the welcome email for a not-yet-onboarded admin" do
      user = create(:user, email: "pending-staff@example.com", must_reset_password: true)
      old_password = user.encrypted_password
      membership = create(:agency_membership, user: user, agency: agency)

      perform_enqueued_jobs do
        post resend_invite_platform_agency_agency_membership_path(agency, membership)
      end

      expect(response).to redirect_to(platform_agency_path(agency))
      expect(user.reload.encrypted_password).not_to eq(old_password)
      expect(user.must_reset_password).to be true
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "pending-staff@example.com" ])
    end

    it "refuses to resend once the admin has already signed in and reset their password" do
      user = create(:user, email: "active-staff@example.com", must_reset_password: false)
      old_password = user.encrypted_password
      membership = create(:agency_membership, user: user, agency: agency)

      expect {
        post resend_invite_platform_agency_agency_membership_path(agency, membership)
      }.not_to change(ActionMailer::Base.deliveries, :count)

      expect(user.reload.encrypted_password).to eq(old_password)
      expect(response).to redirect_to(platform_agency_path(agency))
    end
  end
end

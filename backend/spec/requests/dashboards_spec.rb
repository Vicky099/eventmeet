require "rails_helper"

# Phase 3 — Dashboard Shells (requirement.md §5.14, §5.15 initial wiring, §4.7). Covers the two
# authenticated landing pages themselves; spec/requests/hosting_spec.rb already covers host
# resolution and the (still-live) /admin/__smoke, /platform/__smoke test routes these superseded
# at user_root_path/platform_staff_root_path specifically.
RSpec.describe "Dashboards", type: :request do
  describe "Admin Console dashboard" do
    before { host! "acme.example.com" }

    it "redirects an unauthenticated request to the tenant login" do
      create(:account, subdomain_slug: "acme")

      get user_root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders empty-state stat widgets for a signed-in tenant admin" do
      account = create(:account, subdomain_slug: "acme")
      user = create(:user, email: "owner@acme.example")
      create(:account_membership, user: user, account: account, role: :event_admin)
      sign_in user, scope: :user

      get user_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Events")
      expect(response.body).to include("Participants")
      expect(response.body).to include("No events yet")
    end

    # requirement.md revisit: "design the best Analytics for main dashboard" — the account-wide
    # portfolio overview one level up from a single event's own Analytics page (admin/events#show).
    # Fixed-hierarchy pivot (requirement.md revisit): no more "Needs Attention" section — there's
    # no Super-Admin-review/rejection state left for an event to be stuck in.
    it "shows account-wide analytics — Live Now, Upcoming Events, status breakdown, and registrations trend" do
      account = create(:account, subdomain_slug: "acme")
      user = create(:user, email: "owner@acme.example")
      create(:account_membership, user: user, account: account, role: :event_admin)
      Current.account = account

      live_event = create(:event, account: account, name: "Live Expo", status: :live)
      create(:participant, account: account, event: live_event)
      checked_in = create(:participant, account: account, event: live_event)
      create(:scan_event, account: account, event: live_event, participant: checked_in, scan_type: :check_in, session: nil)

      upcoming_event = create(:event, account: account, name: "Future Summit", status: :up_coming, starts_at: 3.days.from_now, ends_at: 4.days.from_now)

      Current.account = nil
      sign_in user, scope: :user

      get user_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Live Now")
      expect(response.body).to include(live_event.name)
      expect(response.body).to include("Upcoming Events")
      expect(response.body).to include(upcoming_event.name)
      expect(response.body).to include("Events by Status")
      expect(response.body).to include("Registrations Over Time")
    end
  end

  describe "Platform Console dashboard" do
    before { host! "example.com" }

    it "redirects an unauthenticated request to the platform login" do
      get platform_staff_root_path

      expect(response).to redirect_to(new_platform_staff_session_path)
    end

    it "renders the real tenant count for a signed-in Super Admin" do
      create(:account)
      create(:account)
      staff = create(:user, :platform_staff)
      sign_in staff, scope: :platform_staff

      get platform_staff_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tenants")
      expect(response.body).to include(Account.count.to_s)
      expect(response.body).to include("Agencies")
      expect(response.body).to include(Agency.count.to_s)
      expect(response.body).to include("Cross-Tenant Live Pulse")
    end

    # requirement.md revisit: "generate the proper analytics for super admin. earning and all.
    # also include one glance overview. due invoices need actions."
    it "shows real revenue (by agency and platform-wide), and lets a draft/under_review invoice be actioned directly from the dashboard" do
      staff = create(:user, :platform_staff)
      agency = create(:agency, name: "Sparkle Events Agency")
      account = create(:account, agency: agency, name: "Acme Tenant")
      Current.account = account
      paid_event = create(:event, account: account, status: :completed, name: "Paid Event")
      draft_event = create(:event, account: account, status: :completed, name: "Draft Invoice Event")
      review_event = create(:event, account: account, status: :completed, name: "Under Review Event")
      create(:invoice, :paid, event: paid_event, account: account, amount: 15_000)
      draft_invoice = create(:invoice, event: draft_event, account: account, amount: 8_000)
      review_invoice = create(:invoice, :under_review, event: review_event, account: account, amount: 5_000)
      Current.account = nil

      sign_in staff, scope: :platform_staff
      get platform_staff_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Revenue Collected")
      expect(response.body).to include("15,000")
      expect(response.body).to include("Revenue by Agency")
      expect(response.body).to include("Sparkle Events Agency")
      expect(response.body).to include("Invoices Needing Action")
      expect(response.body).to include("Draft Invoice Event")
      expect(response.body).to include("Under Review Event")
      expect(response.body).not_to include("Paid Event") # already paid — not an action item

      # The action buttons are real, not decorative — Send actually delivers the draft.
      post deliver_platform_invoice_path(draft_invoice)
      expect(draft_invoice.reload).to be_awaiting_payment

      # ...and Verify actually marks the under_review one paid.
      post verify_platform_invoice_path(review_invoice)
      expect(review_invoice.reload).to be_paid
    end

    # requirement.md revisit: "as whatsApp is paid i want to track the usage and the approx
    # amount ... all the whatsApp messages count and approx spend on whatsApp messages." Platform-
    # wide total, every agency's own usage combined — spec/requests/super_admin_agencies_spec.rb's
    # own "shows an event's own WhatsApp message count..." test has the identical
    # sent-only/failed-excluded coverage scoped to one agency.
    it "shows the platform-wide WhatsApp message count and an approx spend against it" do
      staff = create(:user, :platform_staff)
      account = create(:account)
      Current.account = account
      event = create(:event, account: account)
      invoice = create(:invoice, :awaiting_payment, event: event, account: account)
      create_list(:notification, 3, account: account, notifiable: invoice, channel: :whatsapp, status: :sent)
      create(:notification, account: account, notifiable: invoice, channel: :whatsapp, status: :failed)
      Current.account = nil

      sign_in staff, scope: :platform_staff
      get platform_staff_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WhatsApp Messages Sent")
      expect(response.body).to include("Approx. WhatsApp Spend")

      tenants_label = Nokogiri::HTML(response.body).css("h6").find { |h6| h6.text.strip == "WhatsApp Messages Sent" }
      expect(tenants_label.parent.at_css("h4").text.strip).to eq("3")

      expected_spend = ActionController::Base.helpers.number_to_currency(3 * Rails.application.config.x.whatsapp_message_cost, unit: "₹", format: "%u%n")
      spend_label = Nokogiri::HTML(response.body).css("h6").find { |h6| h6.text.strip == "Approx. WhatsApp Spend" }
      expect(spend_label.parent.at_css("h4").text).to include(expected_spend)
    end
  end
end

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
      create(:account_membership, user: user, account: account, role: :owner)
      sign_in user, scope: :user

      get user_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Events")
      expect(response.body).to include("Participants")
      expect(response.body).to include("No events yet")
    end

    # requirement.md revisit: "design the best Analytics for main dashboard" — the account-wide
    # portfolio overview one level up from a single event's own Analytics page (admin/events#show).
    it "shows account-wide analytics — Live Now, Upcoming Events, status breakdown, registrations trend, and Needs Attention" do
      account = create(:account, subdomain_slug: "acme")
      user = create(:user, email: "owner@acme.example")
      create(:account_membership, user: user, account: account, role: :owner)
      Current.account = account

      live_event = create(:event, account: account, name: "Live Expo", status: :live)
      create(:participant, account: account, event: live_event)
      checked_in = create(:participant, account: account, event: live_event)
      create(:scan_event, account: account, event: live_event, participant: checked_in, scan_type: :check_in, session: nil)

      upcoming_event = create(:event, account: account, name: "Future Summit", status: :up_coming, starts_at: 3.days.from_now, ends_at: 4.days.from_now)
      rejected_event = create(:event, account: account, name: "Rejected Meetup", approval_status: :rejected, rejection_reason: "Missing venue details")

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
      expect(response.body).to include("Needs Attention")
      expect(response.body).to include(rejected_event.name)
      expect(response.body).to include("Missing venue details")
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
      expect(response.body).to include("Pending Approvals")
      expect(response.body).to include("Cross-Tenant Live Pulse")
    end
  end
end

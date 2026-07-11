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

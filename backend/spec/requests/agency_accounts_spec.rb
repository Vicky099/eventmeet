require "rails_helper"

# Fixed-hierarchy pivot (requirement.md revisit): AgencyConsole::AccountsController#new/#create —
# the only place a new tenant Account comes into existence now. Companion to
# spec/requests/super_admin_accounts_spec.rb (what's left on the Platform Console side) and
# spec/services/account_provisioning_spec.rb (the transaction/rollback logic this controller sits
# in front of, reused verbatim here with an agency: kwarg).
RSpec.describe "Agency Console tenant provisioning", type: :request do
  include ActiveJob::TestHelper

  describe "access control" do
    it "redirects a signed-out request to the tenant/agency login" do
      create(:agency, subdomain_slug: "acme-agency")
      host! "acme-agency.example.com"

      get new_agency_account_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "a per_event agency" do
    let!(:agency) { create(:agency, subdomain_slug: "acme-agency", events_granted: 5, events_used: 0) }
    let!(:agency_user) { create(:user) }

    before do
      create(:agency_membership, user: agency_user, agency: agency)
      host! "acme-agency.example.com"
      sign_in agency_user, scope: :user
    end

    it "renders the new-tenant form" do
      get new_agency_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Tenant")
    end

    it "creates the Account, its event_admin admin User, and sends a welcome email" do
      expect {
        perform_enqueued_jobs do
          post agency_accounts_path, params: {
            account: {
              name: "Acme Sub Events", subdomain_slug: "acme-sub", admin_email: "tenant-admin@example.com",
              contact_email: "contact@acme-sub.example", contact_num: "+1 555 0100",
              sender_email: "sender@acme-sub.example", time_zone: "UTC"
            }
          }
        end
      }.to change(Account, :count).by(1).and change(User, :count).by(1).and change(AccountMembership, :count).by(2)

      account = Account.find_by!(subdomain_slug: "acme-sub")
      expect(account.agency).to eq(agency)
      expect(response).to redirect_to(agency_root_path)

      # Two memberships: the brand-new tenant admin, plus the existing agency_admin backfilled
      # onto this tenant too (AccountProvisioning's agency: kwarg behavior).
      membership = account.account_memberships.find_by!(user: User.find_by!(email: "tenant-admin@example.com"))
      expect(membership).to be_event_admin

      expect(ActionMailer::Base.deliveries.last.to).to eq([ "tenant-admin@example.com" ])
    end

    it "re-renders with errors and creates nothing when the subdomain slug is invalid" do
      expect {
        post agency_accounts_path, params: {
          account: { name: "Acme Sub Events", subdomain_slug: "www", admin_email: "tenant-admin@example.com" }
        }
      }.not_to change(Account, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "an annual agency with an unpaid contract" do
    let!(:agency) { create(:agency, :annual, subdomain_slug: "acme-agency", annual_price: 500_000) }
    let!(:agency_user) { create(:user) }

    before do
      agency.invoice.destroy
      create(:agency_membership, user: agency_user, agency: agency)
      host! "acme-agency.example.com"
      sign_in agency_user, scope: :user
    end

    it "blocks #new and redirects with an alert" do
      get new_agency_account_path

      expect(response).to redirect_to(agency_root_path)
      follow_redirect!
      expect(response.body).to include("hasn't been paid yet")
    end

    it "blocks #create and provisions nothing" do
      expect {
        post agency_accounts_path, params: {
          account: { name: "Acme Sub Events", subdomain_slug: "acme-sub", admin_email: "tenant-admin@example.com" }
        }
      }.not_to change(Account, :count)

      expect(response).to redirect_to(agency_root_path)
    end
  end

  describe "an annual agency with a paid contract" do
    let!(:agency) { create(:agency, :annual, subdomain_slug: "acme-agency") }
    let!(:agency_user) { create(:user) }

    before do
      create(:agency_membership, user: agency_user, agency: agency)
      host! "acme-agency.example.com"
      sign_in agency_user, scope: :user
    end

    it "allows tenant creation, with no per-event pool to decrement" do
      expect {
        post agency_accounts_path, params: {
          account: {
            name: "Acme Sub Events", subdomain_slug: "acme-sub", admin_email: "tenant-admin@example.com",
            contact_email: "contact@acme-sub.example", contact_num: "+1 555 0100",
            sender_email: "sender@acme-sub.example", time_zone: "UTC"
          }
        }
      }.to change(Account, :count).by(1)

      expect(agency.reload.events_used).to eq(0)
    end
  end
end

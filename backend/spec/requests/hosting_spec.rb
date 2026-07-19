require "rails_helper"

# requirement.md §4.3: the Host header is the single source of truth for which app/audience a
# request belongs to, resolved once and enforced at the routing layer. PLATFORM_DOMAIN is
# "example.com" in test (config/initializers/multi_tenancy.rb) — matches Rails' integration-test
# default host, so no per-example host configuration is needed beyond `host!`.
RSpec.describe "Host-based tenant resolution", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) { create(:user) }
  let!(:staff) { create(:user, :platform_staff) }

  before { create(:account_membership, user: user, account: account, role: :event_admin) }

  it "serves the SuperAdmin Console on the bare apex domain" do
    host! "example.com"
    sign_in staff, scope: :platform_staff
    get "/platform/__smoke"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Running on the apex domain")
  end

  it "requires authentication to reach the Platform Console" do
    host! "example.com"
    get "/platform/__smoke"

    expect(response).to redirect_to(new_platform_staff_session_path)
  end

  it "serves the Admin Console on a real tenant's subdomain" do
    host! "acme.example.com"
    sign_in user, scope: :user
    get "/admin/__smoke"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("acme")
  end

  it "requires authentication to reach the Admin Console" do
    host! "acme.example.com"
    get "/admin/__smoke"

    expect(response).to redirect_to(new_user_session_path)
  end

  it "404s a syntactically valid subdomain with no matching Account before ever checking authentication" do
    host! "doesnotexist.example.com"
    get "/admin/__smoke"

    expect(response).to have_http_status(:not_found)
  end

  it "404s a reserved-word subdomain regardless of whether an Account claims it" do
    host! "www.example.com"
    get "/admin/__smoke"

    expect(response).to have_http_status(:not_found)
  end

  it "never reaches a SuperAdmin:: route from a tenant subdomain" do
    host! "acme.example.com"
    sign_in user, scope: :user
    get "/platform/__smoke"

    expect(response).to have_http_status(:not_found)
  end

  it "never reaches a tenant route from the apex domain" do
    host! "example.com"
    sign_in staff, scope: :platform_staff
    get "/admin/__smoke"

    expect(response).to have_http_status(:not_found)
  end

  it "responds to /up regardless of host" do
    host! "example.com"
    get "/up"
    expect(response).to have_http_status(:ok)

    host! "acme.example.com"
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  # Fixed-hierarchy pivot (requirement.md revisit): the Agency Console shares this exact same
  # subdomain routing constraint and the exact same :user Devise login — TenantResolvable's own
  # lenient resolution (Account first, then Agency) is what actually tells the two consoles apart,
  # not a separate constraint/scope (see that concern's own comment).
  describe "Agency Console" do
    let!(:agency) { create(:agency, subdomain_slug: "acme-agency") }
    let!(:agency_user) { create(:user) }

    before { create(:agency_membership, user: agency_user, agency: agency) }

    it "resolves Current.agency (not Current.account) and serves the Agency Console on a real agency's subdomain" do
      host! "acme-agency.example.com"
      sign_in agency_user, scope: :user

      get agency_root_path

      expect(response).to have_http_status(:ok)
    end

    it "requires authentication to reach the Agency Console" do
      host! "acme-agency.example.com"
      get agency_root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "rejects a correct password for a user with no AgencyMembership on this agency, with the same generic message" do
      host! "acme-agency.example.com"
      outsider = create(:user, email: "outsider@example.com", password: "password123!")

      post user_session_path, params: { user: { email: outsider.email, password: "password123!" } }
      follow_redirect!

      expect(response.body).to include("Invalid email or password")
    end

    it "redirects a tenant-only route to the Agency Console when resolved against an agency subdomain" do
      host! "acme-agency.example.com"
      sign_in agency_user, scope: :user

      get "/admin/__smoke"

      expect(response).to redirect_to(agency_root_path)
    end

    it "redirects the Agency Console's own root to the tenant Admin Console when resolved against a real tenant subdomain" do
      host! "acme.example.com"
      sign_in user, scope: :user

      get agency_root_path

      expect(response).to redirect_to(user_root_path)
    end

    # Regression (found live): the shared admin/sessions login view only ever interpolated
    # Current.account&.name — on an agency subdomain that's always nil (only Current.agency is
    # set), so the page silently rendered "Sign in to continue to ." instead of the agency's name.
    it "shows the agency's own name (not a blank) on its login page" do
      host! "acme-agency.example.com"

      get new_user_session_path

      expect(response.body).to include("Sign in to continue to #{agency.name}.")
    end
  end

  it "sets the Postgres RLS session GUC to the resolved account for the duration of the request" do
    host! "acme.example.com"
    sign_in user, scope: :user
    get "/admin/__smoke"

    # The controller captures current_setting('app.current_account_id', true) into the response
    # body mid-request (see SmokeController#show) — proving the SET half of the mechanism, not
    # just that it gets cleared afterward.
    expect(response.body).to include(account.id)

    # And RESET runs in the controller's `ensure`, so by the time we're back here on the same
    # test connection it's cleared — proving the reset half too.
    current_setting = ActiveRecord::Base.connection.select_value(
      "SELECT current_setting('app.current_account_id', true)"
    )
    expect(current_setting).to be_blank
  end
end

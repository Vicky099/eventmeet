require "rails_helper"

# Platform Console (Super Admin) login — requirement.md §4.9 item 1, apex domain, :platform_staff
# Warden scope. Companion to spec/requests/sessions_spec.rb (tenant :user scope).
RSpec.describe "Platform Console login", type: :request do
  let!(:staff) { create(:user, :platform_staff, email: "root@eventmeet.example", password: "password123!") }

  before { host! "example.com" }

  it "signs in a platform_staff user" do
    post platform_staff_session_path, params: { platform_staff: { email: staff.email, password: "password123!" } }

    expect(response).to redirect_to(platform_staff_root_path)
    follow_redirect!
    expect(response.body).to include(staff.email)
  end

  it "rejects a non-platform_staff user with the same generic message" do
    # active_for_authentication?/inactive_message failures redirect-with-flash — see the
    # equivalent comment in spec/requests/sessions_spec.rb.
    account = create(:account)
    tenant_user = create(:user, email: "tenant@acme.example", password: "password123!")
    create(:account_membership, user: tenant_user, account: account)

    post platform_staff_session_path, params: { platform_staff: { email: tenant_user.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).to include("Invalid email or password")
  end

  it "sets a host-only session cookie — no Domain attribute" do
    post platform_staff_session_path, params: { platform_staff: { email: staff.email, password: "password123!" } }

    set_cookie = response.headers["Set-Cookie"]
    expect(set_cookie).to be_present
    expect(set_cookie).not_to match(/domain=/i)
  end

  it "logs out and clears the session" do
    post platform_staff_session_path, params: { platform_staff: { email: staff.email, password: "password123!" } }

    delete destroy_platform_staff_session_path

    expect(response).to redirect_to(new_platform_staff_session_path) # overridden — see SuperAdmin::SessionsController
  end
end

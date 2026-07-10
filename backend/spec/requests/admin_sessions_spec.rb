require "rails_helper"

# Tenant Admin Console login — requirement.md §4.9 item 1. Companion to
# spec/requests/super_admin_sessions_spec.rb (apex/:platform_staff scope) and
# spec/requests/hosting_spec.rb (host resolution itself).
RSpec.describe "Tenant admin login", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) { create(:user, email: "owner@acme.example", password: "password123!") }

  before do
    create(:account_membership, user: user, account: account, role: :owner)
    host! "acme.example.com"
  end

  it "signs in a user with an AccountMembership on this Account" do
    post user_session_path, params: { user: { email: user.email, password: "password123!" } }

    expect(response).to redirect_to("http://acme.example.com/admin")
    follow_redirect!
    expect(response.body).to include(user.email)
  end

  it "rejects a wrong password with a generic message" do
    post user_session_path, params: { user: { email: user.email, password: "wrong" } }

    expect(response.body).to include("Invalid email or password")
  end

  it "rejects a correct password for a user with no AccountMembership on this Account, with the same generic message" do
    # active_for_authentication?/inactive_message failures redirect-with-flash (same pathway
    # Devise's own locked/unconfirmed checks use), unlike a bad password's inline 422 re-render
    # (see "rejects a wrong password" above) — hence follow_redirect! here but not there.
    outsider = create(:user, email: "outsider@example.com", password: "password123!")

    post user_session_path, params: { user: { email: outsider.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).to include("Invalid email or password")
  end

  it "rejects a user who is a member of a DIFFERENT Account (not this one) with the same generic message" do
    other_account = create(:account, subdomain_slug: "beta")
    other_member = create(:user, email: "owner@beta.example", password: "password123!")
    create(:account_membership, user: other_member, account: other_account, role: :owner)

    post user_session_path, params: { user: { email: other_member.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).to include("Invalid email or password")
  end

  it "rejects a platform_staff user (who by construction holds no AccountMembership) the same way" do
    staff = create(:user, :platform_staff, email: "staff@example.com", password: "password123!")

    post user_session_path, params: { user: { email: staff.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).to include("Invalid email or password")
  end

  it "rejects login when the Account is suspended, even with correct credentials" do
    account.update!(status: :suspended)

    post user_session_path, params: { user: { email: user.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).to include("Invalid email or password")
  end

  it "sets a host-only session cookie — no Domain attribute (requirement.md §4.9 item 1)" do
    post user_session_path, params: { user: { email: user.email, password: "password123!" } }

    set_cookie = response.headers["Set-Cookie"]
    expect(set_cookie).to be_present
    expect(set_cookie).not_to match(/domain=/i)
  end

  it "redirects a must_reset_password user straight to the reset-password form instead of signing them in" do
    user.update!(must_reset_password: true)

    post user_session_path, params: { user: { email: user.email, password: "password123!" } }

    expect(response).to redirect_to(%r{/admin/password/edit\?reset_password_token=})
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Set a new password")
  end

  it "actually signs the user out first, so the reset-password form doesn't bounce them away as already-authenticated" do
    # Regression test: sign_out(resource) is ambiguous once :user and :platform_staff both map to
    # User (class_name:) — this must call sign_out(resource_name) instead. Caught via manual
    # end-to-end QA, not by a narrower unit test, which is why this spec drives the full redirect
    # chain rather than stubbing sign_out.
    user.update!(must_reset_password: true)

    post user_session_path, params: { user: { email: user.email, password: "password123!" } }
    follow_redirect!

    expect(response.body).not_to include("already signed in")
    expect(response.body).to include("Set a new password")
  end

  it "clears must_reset_password once the new password is actually set" do
    user.update!(must_reset_password: true)
    post user_session_path, params: { user: { email: user.email, password: "password123!" } }
    token = response.location[/reset_password_token=(.+)/, 1]

    patch user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword456!", password_confirmation: "newpassword456!" }
    }

    expect(response).to redirect_to("http://acme.example.com/admin")
    expect(user.reload.must_reset_password).to be false
    expect(user.valid_password?("newpassword456!")).to be true
  end

  it "logs out and clears the session" do
    post user_session_path, params: { user: { email: user.email, password: "password123!" } }

    delete destroy_user_session_path

    expect(response).to redirect_to(new_user_session_path) # overridden — see Admin::SessionsController
    get "/admin/__smoke"
    expect(response).to redirect_to(new_user_session_path) # dashboard now requires authentication
  end
end

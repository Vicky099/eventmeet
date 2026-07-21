require "rails_helper"

# requirement.md revisit: sidebar's own "Profile" — used to be a "#" stub (AdminHelper
# #admin_nav_items). Now current_user's own account details + password change
# (Admin::ProfilesController), no :id in the URL — always current_user, never another user.
RSpec.describe "Admin Console profile", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) { create(:user, email: "owner@acme.example", password: "password123!", contact_num: nil) }

  before do
    host! "acme.example.com"
    create(:account_membership, user: user, account: account, role: :event_admin)
    sign_in user, scope: :user
  end

  it "redirects an unauthenticated request to the tenant login" do
    sign_out :user
    get admin_profile_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the current user's own account details" do
    get admin_profile_path
    expect(response.body).to include("owner@acme.example")
  end

  it "updates the editable contact number" do
    patch admin_profile_path, params: { user: { contact_num: "9876543210" } }

    expect(response).to redirect_to(admin_profile_path)
    expect(user.reload.contact_num).to eq("9876543210")
  end

  describe "password change" do
    it "rejects the wrong current password, without changing anything" do
      patch password_admin_profile_path, params: {
        user: { current_password: "wrong-password", password: "newpassword123", password_confirmation: "newpassword123" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?("password123!")).to be true
    end

    it "changes the password with the correct current password, and keeps the session signed in" do
      patch password_admin_profile_path, params: {
        user: { current_password: "password123!", password: "newpassword123", password_confirmation: "newpassword123" }
      }

      expect(response).to redirect_to(admin_profile_path)
      expect(user.reload.valid_password?("newpassword123")).to be true

      # bypass_sign_in must re-serialize the Warden session against the new encrypted_password —
      # otherwise the very next request would silently fail authentication (Devise's session
      # serializer keys off authenticatable_salt, which changes with the password).
      get admin_profile_path
      expect(response).to have_http_status(:ok)
    end
  end
end

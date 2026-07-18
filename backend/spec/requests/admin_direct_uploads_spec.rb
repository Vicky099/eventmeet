require "rails_helper"

# This app's own tenant-scoped replacement for the stock ActiveStorage direct-uploads controller
# (Admin::DirectUploadsController) — computes a tenant-namespaced blob key server-side per
# `scope[type]`, never trusting a client-supplied path. No prior coverage existed for this
# controller at all; added alongside the "participant_document" scope (Document now auto-uploads
# the same way Photo already did — admin/participants/_dynamic_fields.html.erb).
RSpec.describe "Admin Console direct uploads", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  it "creates a blob under a tenant-namespaced key for a participant document" do
    sign_in_with_role(:owner)
    Current.account = account
    event = create(:event, account: account)

    post admin_direct_uploads_path(scope: { type: "participant_document", event_id: event.id }),
      params: { blob: { filename: "id-card.pdf", byte_size: 12, checksum: "abc123==", content_type: "application/pdf" } }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["key"]).to start_with("acme/participants/#{event.id}/document/")
    expect(body["direct_upload"]).to be_present
  end

  it "rejects an unknown scope type" do
    sign_in_with_role(:owner)
    Current.account = account
    event = create(:event, account: account)

    post admin_direct_uploads_path(scope: { type: "not_a_real_scope", event_id: event.id }),
      params: { blob: { filename: "x.png", byte_size: 1, checksum: "abc123==", content_type: "image/png" } }

    expect(response).to have_http_status(:bad_request)
  end
end

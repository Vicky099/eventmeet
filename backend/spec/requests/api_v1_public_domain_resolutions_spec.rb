require "rails_helper"

# Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.3).
# Deliberately unauthenticated (Api::V1::Public::DomainResolutionsController's own comment) —
# called by the Next.js server at the fixed apex address, before any tenant is known.
RSpec.describe "Public domain resolution API", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "example.com" }

  it "resolves the shared subdomain+slug shape with no TenantDomain row needed at all" do
    get api_v1_public_domain_resolution_path, params: { host: "acme.example.com" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("account_slug" => "acme", "kind" => "subdomain")
  end

  it "strips a port from the host param — Next.js's own Host header includes one on any non-default port" do
    get api_v1_public_domain_resolution_path, params: { host: "acme.example.com:5173" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("account_slug" => "acme", "kind" => "subdomain")
  end

  it "resolves a verified custom domain" do
    create(:tenant_domain, account: account, domain: "events.acme-custom.test", kind: :custom, verified_at: Time.current)

    get api_v1_public_domain_resolution_path, params: { host: "events.acme-custom.test" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("account_slug" => "acme", "kind" => "custom")
  end

  it "does not resolve an unverified custom domain" do
    create(:tenant_domain, account: account, domain: "events.acme-custom.test", kind: :custom, verified_at: nil)

    get api_v1_public_domain_resolution_path, params: { host: "events.acme-custom.test" }

    expect(response).to have_http_status(:not_found)
  end

  it "404s for a host that matches nothing" do
    get api_v1_public_domain_resolution_path, params: { host: "not-a-real-tenant.example.com" }

    expect(response).to have_http_status(:not_found)
  end

  # requirement.md §4.9 item 4 — Next.js has no per-tenant credential hardcoded anywhere; it looks
  # one up per request via this same call, proving it's Next.js (not a visitor's browser) via a
  # distinct shared secret, never the OAuth layer itself (that's the chicken-and-egg this exists
  # to resolve).
  describe "with the shared secret" do
    around do |example|
      original = ENV["PUBLIC_SITE_SHARED_SECRET"]
      ENV["PUBLIC_SITE_SHARED_SECRET"] = "shh"
      example.run
      ENV["PUBLIC_SITE_SHARED_SECRET"] = original
    end

    it "also includes the account's own OAuth client credentials" do
      application = account.create_oauth_application!(name: "Test App")

      get api_v1_public_domain_resolution_path, params: { host: "acme.example.com" }, headers: { "X-Public-Site-Secret" => "shh" }

      expect(response.parsed_body).to eq(
        "account_slug" => "acme", "kind" => "subdomain", "client_id" => application.uid, "client_secret" => application.secret
      )
    end

    it "omits credentials when the secret header is missing or wrong" do
      account.create_oauth_application!(name: "Test App")

      get api_v1_public_domain_resolution_path, params: { host: "acme.example.com" }, headers: { "X-Public-Site-Secret" => "wrong" }

      expect(response.parsed_body).to eq("account_slug" => "acme", "kind" => "subdomain")
    end
  end
end

require "rails_helper"

# Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.9 item 2).
# OAuth client-credentials only — no Devise session at all, so specs mint a real Doorkeeper token
# against the account's own oauth_application rather than sign_in.
RSpec.describe "Public event API", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:application) { account.create_oauth_application!(name: "Test App") }
  let!(:token) { Doorkeeper::AccessToken.create!(application: application) }

  before { host! "acme.example.com" }

  def auth_headers(access_token = token)
    { "Authorization" => "Bearer #{access_token.token}" }
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  describe "GET /api/v1/public/events/:slug" do
    it "requires a valid bearer token" do
      event = create_event

      get public_event_path(event.slug)

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token minted for a different account's own application" do
      other_account = create(:account, subdomain_slug: "other")
      other_application = other_account.create_oauth_application!(name: "Other App")
      other_token = Doorkeeper::AccessToken.create!(application: other_application)
      event = create_event

      get public_event_path(event.slug), headers: auth_headers(other_token)

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns content_html exactly as stored, with published/registration_schema" do
      event = create_event(status: :up_coming)
      Current.account = account
      event.update!(published_at: Time.current)
      create(:event_page, event: event, account: account, html: "<h1>Hi</h1><script>alert(1)</script>")
      category = create(:ticket_category, event: event, account: account, name: "General")

      get public_event_path(event.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["content_html"]).to eq("<h1>Hi</h1><script>alert(1)</script>")
      expect(body["published"]).to be true
      expect(body["name"]).to eq(event.name)
      category_json = body["registration_schema"].find { |c| c["id"] == category.id }
      expect(category_json["name"]).to eq("General")
      expect(category_json["catalog_fields"]).to include("first_name")
    end

    it "resolves a draft event with published: false and no content_html required" do
      event = create_event(status: :draft)

      get public_event_path(event.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["published"]).to be false
      expect(response.parsed_body["content_html"]).to be_nil
    end

    it "404s for an unknown slug" do
      create_event

      get public_event_path("not-a-real-event"), headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end

    it "reports seats_remaining as nil when every ticket category is unlimited" do
      event = create_event
      create(:ticket_category, event: event, account: account, total_count: nil)

      get public_event_path(event.slug), headers: auth_headers

      expect(response.parsed_body["seats_remaining"]).to be_nil
    end
  end
end

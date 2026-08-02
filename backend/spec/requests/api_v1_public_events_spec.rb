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
      expect(body["template_key"]).to be_nil
      category_json = body["registration_schema"].find { |c| c["id"] == category.id }
      expect(category_json["name"]).to eq("General")
      expect(category_json["catalog_fields"]).to include("first_name")
    end

    # doc/event_page_templates_plan.md, Stage 4 — one of "template_1".."template_3", reported
    # exactly like content_html always has been: whatever this event's own EventPage row actually
    # holds, with no separate draft-state branching in this controller (see the next example —
    # the `published` gate alone is what Next.js keys its own fallback-page decision off of).
    it "returns the assigned template_key when a numbered template is chosen instead of Custom HTML" do
      event = create_event(status: :up_coming)
      Current.account = account
      event.update!(published_at: Time.current)
      create(:event_page, event: event, account: account, template_key: :template_3)

      get public_event_path(event.slug), headers: auth_headers

      body = response.parsed_body
      expect(body["template_key"]).to eq("template_3")
      expect(body["content_html"]).to eq("")
    end

    it "resolves a draft event with published: false and no content_html/template_key required" do
      event = create_event(status: :draft)

      get public_event_path(event.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["published"]).to be false
      expect(response.parsed_body["content_html"]).to be_nil
      expect(response.parsed_body["template_key"]).to be_nil
    end

    it "reports a real template_key even on a still-draft event — the API doesn't gate on published, Next.js does" do
      event = create_event(status: :draft)
      Current.account = account
      create(:event_page, event: event, account: account, template_key: :template_1)

      get public_event_path(event.slug), headers: auth_headers

      body = response.parsed_body
      expect(body["published"]).to be false
      expect(body["template_key"]).to eq("template_1")
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

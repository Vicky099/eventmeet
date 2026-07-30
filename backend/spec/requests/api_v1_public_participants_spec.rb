require "rails_helper"

# Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.9 item 2's
# "register participant"). Reuses the exact same Participant validations/callbacks the admin
# manual-entry form goes through (spec/requests/admin_participants_spec.rb's own dedupe coverage) —
# this file focuses on what's actually new here: OAuth auth, the capacity check, and the
# approval-gated status.
RSpec.describe "Public participant registration API", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:application) { account.create_oauth_application!(name: "Test App") }
  let!(:token) { Doorkeeper::AccessToken.create!(application: application) }

  before { host! "acme.example.com" }

  def auth_headers
    { "Authorization" => "Bearer #{token.token}" }
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  # A category with no RegistrationForm of its own falls back to
  # RegistrationForm::BUILTIN_DEFAULT_CATALOG, which requires photo/document (Event::
  # PARTICIPANT_FIELD_CATALOG's own v12 revisit) — irrelevant to what these specs are actually
  # testing (capacity/dedupe/approval-status), so every category here gets an explicit form with
  # no extra catalog fields turned on, same "narrow the requirement" pattern
  # spec/requests/admin_participants_spec.rb's own fixed-field tests already use.
  def create_category(event, **attrs)
    Current.account = account
    form = create(:registration_form, account: account, event: event)
    create(:ticket_category, event: event, account: account, registration_form: form, **attrs)
  end

  describe "POST /api/v1/public/events/:slug/participants" do
    it "requires a valid bearer token" do
      event = create_event
      category = create_category(event)

      post public_event_participants_path(event.slug),
        params: { participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: category.id } }

      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a confirmed participant when the event doesn't require approval" do
      event = create_event(participant_approval_required: false)
      category = create_category(event)

      expect {
        post public_event_participants_path(event.slug), headers: auth_headers,
          params: { participant: { first_name: "Alice", last_name: "Smith", email: "alice@example.com", ticket_category_id: category.id } }
      }.to change { Event.unscoped_across_tenants { Participant.count } }.by(1)

      expect(response).to have_http_status(:created)
      Current.account = account
      participant = Participant.find_by!(email: "alice@example.com")
      expect(participant.status).to eq("confirmed")
      expect(participant.source).to eq("client_api")
    end

    it "creates a pending participant when the event requires approval" do
      event = create_event(participant_approval_required: true)
      category = create_category(event)

      post public_event_participants_path(event.slug), headers: auth_headers,
        params: { participant: { first_name: "Bob", last_name: "Jones", email: "bob@example.com", ticket_category_id: category.id } }

      Current.account = account
      expect(Participant.find_by!(email: "bob@example.com").status).to eq("pending")
    end

    it "rejects a duplicate registration, same dedupe rules the admin console enforces" do
      event = create_event
      category = create_category(event)
      create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")

      expect {
        post public_event_participants_path(event.slug), headers: auth_headers,
          params: { participant: { first_name: "Alice", last_name: "Smith", email: "alice@example.com", ticket_category_id: category.id } }
      }.not_to change { Event.unscoped_across_tenants { Participant.count } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("validation_failed")
    end

    it "rejects registration once a capacity-tracked category is full" do
      event = create_event
      category = create_category(event, total_count: 1)
      create(:participant, account: account, event: event, ticket_category: category)

      post public_event_participants_path(event.slug), headers: auth_headers,
        params: { participant: { first_name: "Late", last_name: "Comer", email: "late@example.com", ticket_category_id: category.id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("sold_out")
      Current.account = account
      expect(Participant.exists?(email: "late@example.com")).to be false
    end

    it "still allows registration against an unlimited category with any number of existing participants" do
      event = create_event
      category = create_category(event, total_count: nil)
      create(:participant, account: account, event: event, ticket_category: category)

      post public_event_participants_path(event.slug), headers: auth_headers,
        params: { participant: { first_name: "Another", last_name: "Guest", email: "guest@example.com", ticket_category_id: category.id } }

      expect(response).to have_http_status(:created)
    end

    it "404s for an unknown ticket category" do
      event = create_event

      post public_event_participants_path(event.slug), headers: auth_headers,
        params: { participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: SecureRandom.uuid } }

      expect(response).to have_http_status(:not_found)
    end
  end
end

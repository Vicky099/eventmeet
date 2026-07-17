require "rails_helper"

# Phase 7 — Participant Lifecycle (requirement.md §3.4, §5.4).
RSpec.describe "Admin Console participants", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  def participant_count
    Event.unscoped_across_tenants { Participant.count }
  end

  describe "access control" do
    it "redirects an unauthenticated request to the tenant login" do
      event = create_event
      get admin_event_participants_path(event)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "blocks checkin_staff from creating a participant" do
      event = create_event
      sign_in_with_role(:checkin_staff)

      expect {
        post admin_event_participants_path(event), params: { participant: { first_name: "Alice" } }
      }.not_to change { participant_count }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "GET /admin/events/:event_id/participants" do
    before { sign_in_with_role(:owner) }

    it "lists and searches participants across identifier fields" do
      event = create_event
      Current.account = account
      create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")
      create(:participant, account: account, event: event, first_name: "Bob", last_name: "Jones", email: "bob@example.com")

      get admin_event_participants_path(event), params: { q: "alice" }

      expect(response.body).to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end

    it "shows each participant's hex_id as their ID column" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith")

      get admin_event_participants_path(event)

      expect(response.body).to include(participant.hex_id)
    end
  end

  # requirement.md §5.4/§5.14 v12 revisit: "whatever fields we have enabled in [the registration
  # form] only those fields will be present while registration — the rest will be hidden." A
  # disabled catalog field doesn't just render optional — it doesn't render at all. Asserted via
  # each field's own `for="participant_FIELD"` label attribute, not a bare text match — every
  # rendered (enabled) field's label also carries a trailing `<span class="text-danger"> *</span>`
  # (every field that renders is now always required), so a plain ">Company<"-style check would
  # never match a real enabled field in the first place.
  describe "GET participants/new and /:id/edit (field visibility)" do
    before { sign_in_with_role(:owner) }

    it "only shows catalog fields the selected ticket_category's form has enabled" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => true, "department" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      participant = create(:participant, account: account, event: event, ticket_category: category)

      get edit_admin_event_participant_path(event, participant)

      expect(response.body).to include('for="participant_company"')
      expect(response.body).not_to include('for="participant_department"')
    end

    it "shows only first_name (always forced) when no ticket_category is selected yet" do
      event = create_event

      get new_admin_event_participant_path(event)

      expect(response.body).to include('for="participant_first_name"')
      expect(response.body).not_to include('for="participant_company"')
      expect(response.body).not_to include('for="participant_email"')
    end
  end

  describe "POST /admin/events/:event_id/participants" do
    before { sign_in_with_role(:owner) }

    it "creates a participant with source: manual and the event's default status" do
      event = create_event

      post admin_event_participants_path(event), params: { participant: { first_name: "Alice", last_name: "Smith", email: "alice@example.com" } }

      participant = Event.unscoped_across_tenants { Participant.find_by!(name: "Alice Smith") }
      expect(participant.source).to eq("manual")
      expect(participant.status).to eq("confirmed")
      expect(response).to redirect_to(admin_event_participants_path(event))
    end

    it "starts pending when the event requires participant approval" do
      event = create_event(participant_approval_required: true)

      post admin_event_participants_path(event), params: { participant: { first_name: "Alice", last_name: "Smith" } }

      participant = Event.unscoped_across_tenants { Participant.find_by!(name: "Alice Smith") }
      expect(participant.status).to eq("pending")
    end

    # Phase 7.5 — requiredness now comes from the selected ticket_category's own resolved form,
    # not the event as a whole.
    it "requires a fixed-catalog field the chosen ticket_category's form has turned on" do
      event = create_event
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect {
        post admin_event_participants_path(event), params: { participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: category.id } }
      }.not_to change { participant_count }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires a document when the chosen ticket category demands one" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, document_required: true)

      expect {
        post admin_event_participants_path(event), params: { participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: category.id } }
      }.not_to change { participant_count }

      expect(response).to have_http_status(:unprocessable_content)
    end

    # Phase 7.5 — custom fields live on the chosen ticket_category's own resolved RegistrationForm
    # now, not the event as a whole, so the request must select a category whose form actually
    # carries the field being posted.
    it "stores a custom field response, including a required one" do
      event = create_event
      Current.account = account
      registration_form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: registration_form)
      field = create(:custom_field, account: account, registration_form: registration_form, label: "Dietary Needs", required: true)

      post admin_event_participants_path(event), params: {
        participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: category.id, custom_field_values: { field.id.to_s => "Vegetarian" } }
      }

      participant = Event.unscoped_across_tenants { Participant.find_by!(name: "Alice Smith") }
      expect(participant.custom_field_values[field.id.to_s]).to eq("Vegetarian")
    end

    # requirement.md bug report: "uploaded photo then click Add Participant then error on form
    # ... fill mandatory fields ... click Add Participant = my photo automatically gets removed."
    # A failed #create only has the just-uploaded photo attached in memory (apply_uploads ran
    # before the failing #save) — that in-memory attachment dies with the request unless its blob
    # signed_id rides along on the retry too, which admin/participants/_dynamic_fields's hidden
    # field (seeded via shared/_upload_progress) now carries forward automatically.
    it "carries an in-memory-attached photo's signed_id through a failed submission so a retry still attaches it" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => true, "photo" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")

      post admin_event_participants_path(event), params: {
        participant: { first_name: "Alice", last_name: "Smith", ticket_category_id: category.id, photo: blob.signed_id }
      }

      expect(response).to have_http_status(:unprocessable_content)
      hidden_field = Nokogiri::HTML(response.body).at_css('input[name="participant[photo]"]')
      expect(hidden_field["value"]).to eq(blob.signed_id)

      post admin_event_participants_path(event), params: {
        participant: { first_name: "Alice", last_name: "Smith", company: "Acme", ticket_category_id: category.id, photo: blob.signed_id }
      }

      participant = Event.unscoped_across_tenants { Participant.find_by!(name: "Alice Smith") }
      expect(participant.photo).to be_attached
    end

    it "rejects a duplicate participant (dedupe chain)" do
      event = create_event
      Current.account = account
      create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")

      expect {
        post admin_event_participants_path(event), params: { participant: { first_name: "Alice", last_name: "Smith", email: "alice@example.com" } }
      }.not_to change { participant_count }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/events/:event_id/participants/:id/approve" do
    before { sign_in_with_role(:owner) }

    it "confirms a pending participant" do
      event = create_event(participant_approval_required: true)
      Current.account = account
      participant = create(:participant, account: account, event: event, status: :pending)

      patch approve_admin_event_participant_path(event, participant)

      expect(Event.unscoped_across_tenants { participant.reload }.status).to eq("confirmed")
    end
  end

  describe "POST /admin/events/:event_id/participants/bulk_destroy" do
    before { sign_in_with_role(:owner) }

    it "removes only the selected participants" do
      event = create_event
      Current.account = account
      keep = create(:participant, account: account, event: event, first_name: "Keep", last_name: "Me")
      remove_a = create(:participant, account: account, event: event, first_name: "Remove", last_name: "A")
      remove_b = create(:participant, account: account, event: event, first_name: "Remove", last_name: "B")

      expect {
        post bulk_destroy_admin_event_participants_path(event), params: { participant_ids: [ remove_a.id, remove_b.id ] }
      }.to change { participant_count }.by(-2)

      remaining = Event.unscoped_across_tenants { event.participants.pluck(:name) }
      expect(remaining).to eq([ "Keep Me" ])
    end
  end

  describe "cross-tenant isolation (requirement.md §4.2)" do
    it "never returns another tenant's participants in search results" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account)
      create(:participant, account: other_account, event: other_event, first_name: "Other", last_name: "Tenant Person")

      event = create_event
      sign_in_with_role(:owner)

      get admin_event_participants_path(event)

      expect(response.body).not_to include("Other Tenant Person")
    end

    it "404s when Account A requests Account B's event's participants" do
      other_account = create(:account, subdomain_slug: "other2")
      Current.account = other_account
      other_event = create(:event, account: other_account)

      sign_in_with_role(:owner)

      get admin_event_participants_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end
  end
end

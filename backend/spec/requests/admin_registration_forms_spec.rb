require "rails_helper"

# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Standalone,
# named forms: build one, then assign it to whichever ticket categories should use it — including
# all of them at once.
RSpec.describe "Admin Console registration forms", type: :request do
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

  def registration_form_count
    Event.unscoped_across_tenants { RegistrationForm.count }
  end

  describe "access control" do
    it "redirects an unauthenticated request to the tenant login" do
      event = create_event
      get admin_event_registration_forms_path(event)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "blocks checkin_staff from viewing registration forms" do
      event = create_event
      sign_in_with_role(:checkin_staff)

      get admin_event_registration_forms_path(event)

      expect(response).to redirect_to(user_root_path)
    end

    it "allows event_manager to view and create registration forms" do
      event = create_event
      sign_in_with_role(:event_manager)

      get admin_event_registration_forms_path(event)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/events/:event_id/registration_forms" do
    before { sign_in_with_role(:owner) }

    it "lists forms and which categories they apply to" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "VIP")
      form = create(:registration_form, account: account, event: event, name: "VIP Form")
      category.update!(registration_form: form)

      get admin_event_registration_forms_path(event)

      expect(response.body).to include("VIP Form")
      expect(response.body).to include("VIP")
    end

    it "lists categories still on the built-in default" do
      event = create_event
      Current.account = account
      create(:ticket_category, account: account, event: event, name: "General")

      get admin_event_registration_forms_path(event)

      expect(response.body).to include("General")
      expect(response.body).to include("built-in default")
    end
  end

  describe "POST /admin/events/:event_id/registration_forms" do
    before { sign_in_with_role(:owner) }

    it "creates a form with catalog fields and a custom field" do
      event = create_event

      expect {
        post admin_event_registration_forms_path(event), params: {
          registration_form: {
            name: "VIP Form",
            catalog_fields: [ "email", "company" ],
            uniqueness_fields: [ "email" ],
            custom_fields_attributes: { "0" => { label: "Dietary Needs", field_type: "text" } }
          }
        }
      }.to change { registration_form_count }.by(1)

      expect(response).to redirect_to(admin_event_registration_forms_path(event))
      form = Event.unscoped_across_tenants { RegistrationForm.find_by!(name: "VIP Form") }
      expect(form.catalog_fields).to include("email" => true, "company" => true, "department" => false)
      expect(form.uniqueness_fields).to eq([ "email" ])
      expect(Event.unscoped_across_tenants { form.custom_fields.sole.label }).to eq("Dietary Needs")
    end

    # requirement.md v12 revisit: "position each and every field — order of the field should be
    # configurable."
    it "saves configured catalog field positions and a custom field's position" do
      event = create_event

      # Negative positions, not 0/1 — every other (unoverridden) field defaults to its own natural
      # catalog index (0..9), so anything in that range risks colliding with one of them.
      post admin_event_registration_forms_path(event), params: {
        registration_form: {
          name: "Ordered Form",
          catalog_field_positions: { "country" => "-2", "email" => "-1" },
          uniqueness_fields: [ "email" ],
          custom_fields_attributes: { "0" => { label: "Dietary Needs", field_type: "text", position: "2" } }
        }
      }

      form = Event.unscoped_across_tenants { RegistrationForm.find_by!(name: "Ordered Form") }
      expect(form.catalog_field_positions["country"]).to eq(-2)
      expect(form.catalog_field_positions["email"]).to eq(-1)
      expect(form.ordered_catalog_fields.first).to eq("country")
      expect(Event.unscoped_across_tenants { form.custom_fields.sole.position }).to eq(2)
    end

    it "assigns the new form to the selected ticket categories" do
      event = create_event
      Current.account = account
      category_a = create(:ticket_category, account: account, event: event)
      category_b = create(:ticket_category, account: account, event: event)
      untouched = create(:ticket_category, account: account, event: event)

      post admin_event_registration_forms_path(event), params: {
        registration_form: { name: "VIP Form", uniqueness_fields: [ "email" ], ticket_category_ids: [ category_a.id, category_b.id ] }
      }

      Event.unscoped_across_tenants do
        form = RegistrationForm.find_by!(name: "VIP Form")
        expect(category_a.reload.registration_form).to eq(form)
        expect(category_b.reload.registration_form).to eq(form)
        expect(untouched.reload.registration_form).to be_nil
      end
    end

    # requirement.md: "if one form is for all category then we should have that feasibility as
    # well. create one form and apply for all ticket category."
    it "applies the new form to every ticket category when apply_to_all is checked" do
      event = create_event
      Current.account = account
      category_a = create(:ticket_category, account: account, event: event)
      category_b = create(:ticket_category, account: account, event: event)

      post admin_event_registration_forms_path(event), params: {
        registration_form: { name: "Shared Form", uniqueness_fields: [ "email" ], apply_to_all: "1" }
      }

      Event.unscoped_across_tenants do
        form = RegistrationForm.find_by!(name: "Shared Form")
        expect(category_a.reload.registration_form).to eq(form)
        expect(category_b.reload.registration_form).to eq(form)
      end
    end

    # A real report: an organizer created and configured a form, believed it was "assigned to
    # all," and it wasn't — nothing had actually been checked on the Assign step. Surfaced
    # immediately as a flash warning now, not just passively on the next index visit.
    it "warns immediately when a new form isn't assigned to any category" do
      event = create_event
      Current.account = account
      create(:ticket_category, account: account, event: event)

      post admin_event_registration_forms_path(event), params: { registration_form: { name: "Orphan Form", uniqueness_fields: [ "email" ] } }

      follow_redirect!
      expect(response.body).to include("isn&#39;t assigned to any ticket category yet")
    end

    it "does not warn when categories are actually assigned" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)

      post admin_event_registration_forms_path(event), params: {
        registration_form: { name: "Assigned Form", uniqueness_fields: [ "email" ], ticket_category_ids: [ category.id ] }
      }

      follow_redirect!
      expect(response.body).not_to include("isn&#39;t assigned to any ticket category yet")
    end

    it "re-renders with errors, preserving the attempted custom field, when the form is invalid" do
      event = create_event

      post admin_event_registration_forms_path(event), params: {
        registration_form: {
          name: "",
          custom_fields_attributes: { "0" => { label: "Meal", field_type: "dropdown", options: "" } }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Meal")
    end

    # requirement.md revisit: "At least one uniqueness parameter should be set."
    it "re-renders with errors when no uniqueness field is checked" do
      event = create_event

      post admin_event_registration_forms_path(event), params: { registration_form: { name: "No Dedupe Form" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("select at least one field")
      expect(registration_form_count).to eq(0)
    end
  end

  describe "PATCH /admin/events/:event_id/registration_forms/:id" do
    before { sign_in_with_role(:owner) }

    it "reassigns categories to reflect exactly what's checked, unassigning any left out" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event)
      still_assigned = create(:ticket_category, account: account, event: event, registration_form: form)
      unassigned = create(:ticket_category, account: account, event: event, registration_form: form)
      newly_assigned = create(:ticket_category, account: account, event: event)

      patch admin_event_registration_form_path(event, form), params: {
        registration_form: { name: form.name, uniqueness_fields: [ "email" ], ticket_category_ids: [ still_assigned.id, newly_assigned.id ] }
      }

      Event.unscoped_across_tenants do
        expect(still_assigned.reload.registration_form).to eq(form)
        expect(newly_assigned.reload.registration_form).to eq(form)
        expect(unassigned.reload.registration_form).to be_nil
      end
    end

    # Same enforcement TicketCategory#effective_catalog_fields already guarantees regardless of
    # what's saved on the form itself — a request that omits the badge-mandated field from the
    # submitted catalog_fields still can't turn its requiredness off.
    it "keeps a badge-mandated field effectively required even if the submitted catalog_fields omits it" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      create(:badge, account: account, event: event, ticket_category: category, content: "<div>$DESIGNATION$</div>")

      patch admin_event_registration_form_path(event, form), params: {
        registration_form: { name: form.name, catalog_fields: [ "company" ], uniqueness_fields: [ "email" ], ticket_category_ids: [ category.id ] }
      }

      Event.unscoped_across_tenants do
        expect(form.reload.catalog_fields["position"]).to be false # the organizer's own raw config
        expect(category.reload.effective_catalog_fields["position"]).to be true # still enforced
      end
    end
  end

  describe "DELETE /admin/events/:event_id/registration_forms/:id" do
    before { sign_in_with_role(:owner) }

    it "removes the form and unassigns (does not destroy) any category using it" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect {
        delete admin_event_registration_form_path(event, form)
      }.to change { registration_form_count }.by(-1)

      Event.unscoped_across_tenants do
        expect(TicketCategory.exists?(category.id)).to be true
        expect(category.reload.registration_form).to be_nil
      end
    end
  end

  describe "cross-tenant isolation (requirement.md §4.2)" do
    it "404s when Account A requests Account B's event's registration forms" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account)

      sign_in_with_role(:owner)

      # config.action_dispatch.show_exceptions = :rescuable in test (config/environments/test.rb)
      # — ActiveRecord::RecordNotFound is one of Rails' own "rescuable" exceptions, rendered as a
      # real 404 response rather than propagating as a Ruby exception.
      get admin_event_registration_forms_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end
  end
end

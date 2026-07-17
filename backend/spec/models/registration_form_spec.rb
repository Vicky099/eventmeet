require "rails_helper"

# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Standalone forms
# an organizer builds once, then assigns to whichever TicketCategory rows should use them
# (TicketCategory#belongs_to :registration_form) — including all of them at once, which is just
# assigning the same form to every category, not a separate concept.
RSpec.describe RegistrationForm, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:registration_form, account: account, event: event)).to be_valid
  end

  it "requires a name" do
    expect(build(:registration_form, account: account, event: event, name: nil)).not_to be_valid
  end

  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... At least one uniqueness parameter should be set."
  describe "uniqueness_fields" do
    it "requires at least one uniqueness field" do
      form = build(:registration_form, account: account, event: event, uniqueness_fields: [])

      expect(form).not_to be_valid
      expect(form.errors[:uniqueness_fields].join).to include("select at least one field")
    end

    it "rejects a field outside the recognized set" do
      form = build(:registration_form, account: account, event: event, uniqueness_fields: [ "email", "govt_id" ])

      expect(form).not_to be_valid
      expect(form.errors[:uniqueness_fields].join).to include("govt_id")
    end

    it "is valid with a single recognized field" do
      expect(build(:registration_form, account: account, event: event, uniqueness_fields: [ "contact_num" ])).to be_valid
    end

    it "is valid with both recognized fields" do
      expect(build(:registration_form, account: account, event: event, uniqueness_fields: %w[email contact_num])).to be_valid
    end
  end

  it "defaults catalog_fields to every catalog entry present and false" do
    form = RegistrationForm.new(account: account, event: event)

    expect(form.catalog_fields).to eq(Event::PARTICIPANT_FIELD_CATALOG.index_with { false })
  end

  it "preserves explicitly-set catalog_fields values over the default" do
    form = RegistrationForm.new(account: account, event: event, catalog_fields: { "email" => true })

    expect(form.catalog_fields["email"]).to be true
    expect(form.catalog_fields["company"]).to be false
  end

  # requirement.md v12 revisit: "I want to position each and every field ... order of the field
  # should be configurable."
  describe "field ordering" do
    it "defaults catalog_field_positions to each field's own index in the catalog" do
      form = RegistrationForm.new(account: account, event: event)

      expect(form.catalog_field_positions).to eq(Event::PARTICIPANT_FIELD_CATALOG.each_with_index.to_h)
    end

    it "preserves explicitly-set positions over the default" do
      form = RegistrationForm.new(account: account, event: event, catalog_field_positions: { "country" => 0 })

      expect(form.catalog_field_positions["country"]).to eq(0)
      expect(form.catalog_field_positions["email"]).to eq(Event::PARTICIPANT_FIELD_CATALOG.index("email"))
    end

    it "#ordered_catalog_fields sorts the catalog by configured position" do
      # Negative positions, not 0/1/2 — every other (unoverridden) field defaults to its own
      # natural catalog index (0..6), so anything in that range risks colliding with one of them;
      # negative values unambiguously sort before all of them regardless.
      form = create(:registration_form, account: account, event: event,
        catalog_field_positions: { "country" => -3, "email" => -2, "company" => -1 })

      expect(form.ordered_catalog_fields.first(3)).to eq(%w[country email company])
    end

    it "TicketCategory#ordered_catalog_fields falls back to the catalog's own order with no form assigned" do
      category = create(:ticket_category, account: account, event: event)

      expect(category.ordered_catalog_fields).to eq(Event::PARTICIPANT_FIELD_CATALOG)
    end

    it "TicketCategory#ordered_catalog_fields reflects the assigned form's configured order" do
      form = create(:registration_form, account: account, event: event, catalog_field_positions: { "country" => -1 })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(category.ordered_catalog_fields.first).to eq("country")
    end
  end

  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... same parameter should be used while importing the data."
  describe "TicketCategory#effective_uniqueness_fields" do
    it "returns nil (Participant.duplicate_match's own full-cascade default) with no form assigned" do
      category = create(:ticket_category, account: account, event: event)

      expect(category.effective_uniqueness_fields).to be_nil
    end

    it "reflects the assigned form's own configured uniqueness_fields" do
      form = create(:registration_form, account: account, event: event, uniqueness_fields: [ "contact_num" ])
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(category.effective_uniqueness_fields).to eq([ "contact_num" ])
    end
  end

  describe "assigning to ticket categories" do
    it "can be assigned to several ticket categories at once — 'apply to all' is just this" do
      form = create(:registration_form, account: account, event: event)
      category_a = create(:ticket_category, account: account, event: event, registration_form: form)
      category_b = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(form.ticket_categories).to contain_exactly(category_a, category_b)
      expect(category_a.registration_form).to eq(form)
      expect(category_b.registration_form).to eq(form)
    end

    it "nullifies (does not destroy) assigned categories when the form is deleted" do
      form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      form.destroy!

      expect(category.reload.registration_form_id).to be_nil
    end
  end

  # Phase 7.5 — the badge-mandatory rule's actual application (requirement.md §5.4/§5.14 v12):
  # "whatever fields are placed on a ticket category's badge design are automatically mandatory on
  # that category's registration form."
  describe "TicketCategory#effective_catalog_fields" do
    it "falls back to RegistrationForm::BUILTIN_DEFAULT_CATALOG when no form is assigned" do
      category = create(:ticket_category, account: account, event: event)

      expect(category.effective_catalog_fields).to eq(
        Event::PARTICIPANT_FIELD_CATALOG.index_with { |field| RegistrationForm::BUILTIN_DEFAULT_CATALOG.include?(field) }
      )
    end

    it "reflects the assigned form's own catalog_fields when no badge is configured" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(category.effective_catalog_fields["company"]).to be true
      expect(category.effective_catalog_fields["email"]).to be false
    end

    it "forces a badge-mandated field to true even when the assigned form doesn't require it" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      create(:badge, account: account, event: event, ticket_category: category, content: "<div>$DESIGNATION$</div>")

      fields = category.effective_catalog_fields
      expect(fields["position"]).to be true
      expect(fields["company"]).to be false # untouched — not on the badge, organizer left it off
    end

    it "applies the category's own badge, not the event's default badge, when both exist" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "department" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      create(:badge, account: account, event: event, ticket_category: nil, content: "<div>$OTHER1$</div>", mapping: { "OTHER1" => "department" })
      create(:badge, account: account, event: event, ticket_category: category, content: "<div>$DESIGNATION$</div>")

      fields = category.effective_catalog_fields
      expect(fields["position"]).to be true
      expect(fields["department"]).to be false # that's the *default* badge's requirement, not this category's
    end

    it "applies badge-mandated fields even when the category is on a form shared with other categories" do
      shared_form = create(:registration_form, account: account, event: event, catalog_fields: { "email" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: shared_form)
      create(:ticket_category, account: account, event: event, registration_form: shared_form) # a sibling on the same form
      create(:badge, account: account, event: event, ticket_category: category, content: "<div>$DESIGNATION$</div>")

      fields = category.effective_catalog_fields
      expect(fields["email"]).to be true # from the shared form
      expect(fields["position"]).to be true # from this category's own badge
    end

    # requirement.md v12 revisit: "title, firstname & lastname in the default fields selection" —
    # first_name joined the catalog but stays effectively required unconditionally, unlike every
    # other catalog field (mirrored by Participant's own unconditional presence validation).
    it "forces first_name to true even when a form explicitly turns it off" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "first_name" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(category.effective_catalog_fields["first_name"]).to be true
    end

    it "forces first_name to true even with no form assigned at all" do
      category = create(:ticket_category, account: account, event: event)

      expect(category.effective_catalog_fields["first_name"]).to be true
    end

    # requirement.md v12 revisit: "add photo and document in the default form" — document's
    # pre-existing ticket_category-level requirement folds in as another forced-true source here,
    # same as first_name/badge-mandated fields, rather than staying a second, independent
    # validation with its own separate error message.
    it "forces document to true when the category itself demands one, even without a form" do
      category = create(:ticket_category, account: account, event: event, document_required: true)

      expect(category.effective_catalog_fields["document"]).to be true
    end

    it "does not force document to true when the category doesn't demand one" do
      # An explicit assigned form with document off — isolates this from
      # RegistrationForm::BUILTIN_DEFAULT_CATALOG (every catalog field, document included, when no
      # form is assigned at all), so the only thing that could turn "document" true here is
      # document_required? itself.
      form = create(:registration_form, account: account, event: event, catalog_fields: { "document" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form, document_required: false)

      expect(category.effective_catalog_fields["document"]).to be false
    end
  end
end

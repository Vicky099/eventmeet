require "rails_helper"

RSpec.describe Participant, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:participant, account: account, event: event)).to be_valid
  end

  it "requires a first name" do
    participant = build(:participant, account: account, event: event, first_name: nil)
    expect(participant).not_to be_valid
  end

  describe "#name derivation (first_name/last_name are the primary captured fields)" do
    it "derives the full name from first_name + last_name" do
      participant = build(:participant, account: account, event: event, first_name: "Jane", last_name: "Doe")
      participant.valid?
      expect(participant.name).to eq("Jane Doe")
    end

    it "omits last_name from the derived name when blank (single-name cultures)" do
      participant = build(:participant, account: account, event: event, first_name: "Cher", last_name: nil)
      participant.valid?
      expect(participant.name).to eq("Cher")
    end
  end

  it "validates email format, allowing blank" do
    expect(build(:participant, account: account, event: event, email: "not-an-email")).not_to be_valid
    expect(build(:participant, account: account, event: event, email: nil)).to be_valid
  end

  describe "identifier generation" do
    it "auto-generates hex_id and client_participant_id when left blank" do
      participant = create(:participant, account: account, event: event)

      expect(participant.hex_id).to be_present
      expect(participant.client_participant_id).to be_present
    end

    it "respects an explicitly-supplied client_participant_id instead of generating one" do
      participant = create(:participant, account: account, event: event, client_participant_id: "VIP-001")
      expect(participant.client_participant_id).to eq("VIP-001")
    end

    it "requires client_participant_id to be unique per event, not globally" do
      create(:participant, account: account, event: event, client_participant_id: "P-1")
      other_event = create(:event, account: account, name: "Other Event")

      same_event_dupe = build(:participant, account: account, event: event, client_participant_id: "P-1")
      other_event_reuse = build(:participant, account: account, event: other_event, client_participant_id: "P-1")

      expect(same_event_dupe).not_to be_valid
      expect(other_event_reuse).to be_valid
    end

    it "requires hex_id to be unique globally, across events" do
      first = create(:participant, account: account, event: event)
      other_event = create(:event, account: account, name: "Other Event")

      dupe = build(:participant, account: account, event: other_event, hex_id: first.hex_id)

      expect(dupe).not_to be_valid
      expect(dupe.errors[:hex_id]).to be_present
    end
  end

  # Phase 13 — Communications, revisited: backs the `$QRCODE$` EmailTemplate placeholder and the
  # built-in confirmation email — encodes hex_id as a base64 data: URI, never uploaded anywhere.
  describe "#qr_code_data_uri" do
    it "returns a base64-inlined PNG data URI" do
      participant = create(:participant, account: account, event: event)

      expect(participant.qr_code_data_uri).to match(%r{\Adata:image/png;base64,[A-Za-z0-9+/=]+\z})
    end

    it "encodes the participant's own hex_id, not client_participant_id" do
      participant = create(:participant, account: account, event: event)

      png = Base64.decode64(participant.qr_code_data_uri.split(",", 2).last)
      expect(RQRCode::QRCode.new(participant.hex_id).as_png(size: 240).to_s).to eq(png)
    end
  end

  describe "#status default" do
    it "does not force a status itself — the caller decides (Event#default_participant_status)" do
      participant = build(:participant, account: account, event: event)
      expect(participant.status).to eq("pending") # the schema's own column default, untouched by this model
    end
  end

  describe "field-level requiredness (requirement.md §5.4)" do
    # Phase 7.5 — the fixed catalog's requiredness source moved off the event-wide
    # Event#participant_fields onto the participant's own ticket_category's assigned form
    # (TicketCategory#effective_catalog_fields); no ticket_category selected means nothing here
    # is enforced at all.
    it "requires a fixed-catalog field only when the participant's ticket_category's form turns it on" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(build(:participant, account: account, event: event, ticket_category: category, company: nil)).not_to be_valid
      expect(build(:participant, account: account, event: event, ticket_category: category, company: "Acme")).to be_valid
    end

    it "requires nothing from the fixed catalog when no ticket_category is selected" do
      expect(build(:participant, account: account, event: event, ticket_category: nil, company: nil)).to be_valid
    end

    # requirement.md v12 revisit: "title, firstname & lastname in the default fields selection" —
    # first_name joined Event::PARTICIPANT_FIELD_CATALOG but stays effectively required no matter
    # what, unlike every other catalog field — a participant needs *some* name regardless of what
    # an organizer configures.
    it "always requires first_name, even with no ticket_category selected" do
      expect(build(:participant, account: account, event: event, ticket_category: nil, first_name: nil)).not_to be_valid
    end

    it "always requires first_name even when a form explicitly turns it off" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "first_name" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      expect(build(:participant, account: account, event: event, ticket_category: category, first_name: nil)).not_to be_valid
    end

    # requirement.md v12 revisit: "add photo and document in the default form" — has_one_attached
    # proxies, so requiredness has to check .attached?, not .blank? (a bare, unattached
    # ActiveStorage::Attached::One is never considered "blank" by ActiveSupport's Object#blank?).
    it "requires photo/document when the catalog turns them on, checking .attached? not .blank?" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "photo" => true, "document" => true })
      category = create(:ticket_category, account: account, event: event, registration_form: form)

      missing = build(:participant, account: account, event: event, ticket_category: category, attach_photo: false, attach_document: false)
      expect(missing).not_to be_valid
      expect(missing.errors[:photo]).to be_present
      expect(missing.errors[:document]).to be_present

      present = build(:participant, account: account, event: event, ticket_category: category)
      expect(present).to be_valid
    end

    # TicketCategory#document_required? (pre-existing, ticket-category-level) folds into
    # #effective_catalog_fields as another forced-true source now, rather than staying a second,
    # independent validation with its own separate error message.
    it "requires document when the ticket category demands one, even without an assigned form" do
      category = create(:ticket_category, account: account, event: event, document_required: true)

      expect(build(:participant, account: account, event: event, ticket_category: category, attach_document: false)).not_to be_valid
    end

    it "requires a fixed-catalog field the participant's category's own badge mandates, even if the form doesn't" do
      form = create(:registration_form, account: account, event: event, catalog_fields: { "company" => false })
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      create(:badge, account: account, event: event, ticket_category: category, content: "<div>$DESIGNATION$</div>")

      expect(build(:participant, account: account, event: event, ticket_category: category, position: nil)).not_to be_valid
    end

    # Phase 7.5 — CustomField moved from Event to RegistrationForm, assigned to whichever
    # ticket_category(s) use that form — no ticket_category, or a category with no form assigned
    # at all, has nothing to require.
    it "requires a CustomField marked required on the participant's own ticket_category's form" do
      registration_form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: registration_form)
      field = create(:custom_field, account: account, registration_form: registration_form, label: "Dietary Needs", required: true)

      missing = build(:participant, account: account, event: event, ticket_category: category)
      expect(missing).not_to be_valid
      expect(missing.errors[:base].join).to include("Dietary Needs")

      present = build(:participant, account: account, event: event, ticket_category: category, custom_field_values: { field.id.to_s => "Vegetarian" })
      expect(present).to be_valid
    end

    it "does not require a CustomField configured on a different ticket_category's form" do
      registration_form = create(:registration_form, account: account, event: event)
      category = create(:ticket_category, account: account, event: event, registration_form: registration_form)
      other_category = create(:ticket_category, account: account, event: event)
      create(:custom_field, account: account, registration_form: registration_form, label: "Dietary Needs", required: true)

      participant = build(:participant, account: account, event: event, ticket_category: other_category)

      expect(participant).to be_valid
    end

    it "requires a document when the selected ticket category demands one" do
      category = create(:ticket_category, account: account, event: event, document_required: true)

      participant = build(:participant, account: account, event: event, ticket_category: category, attach_document: false)

      expect(participant).not_to be_valid
      expect(participant.errors[:document]).to be_present
    end
  end

  describe ".duplicate_match (requirement.md §3.11/§5.4 dedupe chain: govt ID -> email+name -> email -> phone)" do
    it "matches on govt_id first, regardless of other fields" do
      existing = create(:participant, account: account, event: event, govt_id: "GID1", email: "a@example.com", first_name: "Alice", last_name: nil)

      match, tier = Participant.duplicate_match(event: event, govt_id: "GID1", email: "different@example.com", name: "Different Name")

      expect(match).to eq(existing)
      expect(tier).to eq(:govt_id)
    end

    it "falls through to email+name when govt_id doesn't match" do
      existing = create(:participant, account: account, event: event, email: "a@example.com", first_name: "Alice", last_name: nil)

      match, tier = Participant.duplicate_match(event: event, email: "a@example.com", name: "Alice")

      expect(match).to eq(existing)
      expect(tier).to eq(:email_and_name)
    end

    it "falls through to email alone when name differs" do
      existing = create(:participant, account: account, event: event, email: "a@example.com", first_name: "Alice", last_name: nil)

      match, tier = Participant.duplicate_match(event: event, email: "a@example.com", name: "Someone Else")

      expect(match).to eq(existing)
      expect(tier).to eq(:email)
    end

    it "falls through to phone when there's no email at all" do
      existing = create(:participant, account: account, event: event, email: nil, contact_num: "555-1234")

      match, tier = Participant.duplicate_match(event: event, contact_num: "555-1234")

      expect(match).to eq(existing)
      expect(tier).to eq(:contact_num)
    end

    it "finds no match when nothing overlaps" do
      create(:participant, account: account, event: event, email: "a@example.com", contact_num: "555-1234")

      match, tier = Participant.duplicate_match(event: event, email: "b@example.com", contact_num: "555-9999")

      expect(match).to be_nil
      expect(tier).to be_nil
    end

    it "is scoped per event — the same email in a different event is not a duplicate" do
      create(:participant, account: account, event: event, email: "a@example.com")
      other_event = create(:event, account: account, name: "Other Event")

      match, = Participant.duplicate_match(event: other_event, email: "a@example.com")

      expect(match).to be_nil
    end

    it "excludes the record's own id (so editing a participant doesn't flag itself)" do
      participant = create(:participant, account: account, event: event, email: "a@example.com")

      match, = Participant.duplicate_match(event: event, email: "a@example.com", exclude_id: participant.id)

      expect(match).to be_nil
    end

    # requirement.md revisit: "we should have privilege to set the uniqueness for participant
    # data ... unique by email, unique by contact num or both."
    describe "uniqueness_fields (organizer-configured dedupe dimensions)" do
      it "ignores an email match when only contact_num is configured" do
        create(:participant, account: account, event: event, email: "a@example.com", contact_num: "555-0001")

        match, = Participant.duplicate_match(event: event, email: "a@example.com", contact_num: "555-9999", uniqueness_fields: [ "contact_num" ])

        expect(match).to be_nil
      end

      it "still matches on contact_num when only contact_num is configured" do
        existing = create(:participant, account: account, event: event, contact_num: "555-0001")

        match, tier = Participant.duplicate_match(event: event, contact_num: "555-0001", uniqueness_fields: [ "contact_num" ])

        expect(match).to eq(existing)
        expect(tier).to eq(:contact_num)
      end

      it "ignores a contact_num match when only email is configured" do
        create(:participant, account: account, event: event, email: "a@example.com", contact_num: "555-0001")

        match, = Participant.duplicate_match(event: event, email: "b@example.com", contact_num: "555-0001", uniqueness_fields: [ "email" ])

        expect(match).to be_nil
      end

      it "still matches on govt_id regardless of which fields are configured" do
        existing = create(:participant, account: account, event: event, govt_id: "GID1")

        match, tier = Participant.duplicate_match(event: event, govt_id: "GID1", uniqueness_fields: [ "contact_num" ])

        expect(match).to eq(existing)
        expect(tier).to eq(:govt_id)
      end

      it "checks every field again (the original cascade) when uniqueness_fields is nil" do
        existing = create(:participant, account: account, event: event, email: "a@example.com")

        match, = Participant.duplicate_match(event: event, email: "a@example.com", uniqueness_fields: nil)

        expect(match).to eq(existing)
      end
    end
  end

  describe "duplicate validation on create" do
    it "rejects a new participant that matches the dedupe chain" do
      create(:participant, account: account, event: event, email: "a@example.com", first_name: "Alice", last_name: nil)

      dupe = build(:participant, account: account, event: event, email: "a@example.com", first_name: "Alice", last_name: nil)

      expect(dupe).not_to be_valid
      expect(dupe.errors[:base].join).to include("Duplicate of Alice")
    end

    # requirement.md revisit: "same parameter should be used while importing the data" implies
    # the reverse too — manual entry must respect the same per-category config import does.
    it "uses the participant's own ticket_category's configured uniqueness_fields" do
      form = create(:registration_form, account: account, event: event, catalog_fields: {}, uniqueness_fields: [ "contact_num" ])
      category = create(:ticket_category, account: account, event: event, registration_form: form)
      create(:participant, account: account, event: event, ticket_category: category, email: "a@example.com", contact_num: "555-0001")

      not_a_dupe = build(:participant, account: account, event: event, ticket_category: category,
        first_name: "Someone", email: "a@example.com", contact_num: "555-9999")
      dupe = build(:participant, account: account, event: event, ticket_category: category,
        first_name: "Someone Else", email: "b@example.com", contact_num: "555-0001")

      expect(not_a_dupe).to be_valid # email matched, but this category only dedupes on contact_num
      expect(dupe).not_to be_valid
    end
  end

  # requirement.md revisit: "once participant registration start then the government ID will
  # start assign to participant" / "while uploading the govtID it should automatically assign to
  # the participant" — the actual GovtId.assign_to!/#claim_existing_value! behavior is unit-tested
  # directly in spec/models/govt_id_spec.rb; this is just confirming the callback wiring itself
  # fires at the right moment.
  describe "#sync_govt_id_with_pool! (after_create_commit)" do
    it "claims an available pool id when created with no govt_id of its own" do
      create(:govt_id, account: account, event: event, value: "GID-1")

      participant = create(:participant, account: account, event: event, govt_id: nil)

      expect(participant.govt_id).to eq("GID-1")
    end

    it "leaves a manually-provided govt_id alone and reconciles the pool instead" do
      pool_row = create(:govt_id, account: account, event: event, value: "GID-1")

      participant = create(:participant, account: account, event: event, govt_id: "GID-1")

      expect(participant.govt_id).to eq("GID-1")
      expect(pool_row.reload.participant_id).to eq(participant.id)
    end

    it "leaves govt_id nil when the pool has nothing available" do
      participant = create(:participant, account: account, event: event, govt_id: nil)

      expect(participant.govt_id).to be_nil
    end
  end

  # requirement.md revisit: "GOVT ID will be unique by event." #not_a_duplicate already covers
  # create (with a friendlier message); this closes the same gap on update, previously
  # unvalidated entirely.
  describe "govt_id uniqueness on update" do
    it "rejects updating to a govt_id already used by another participant in the same event" do
      create(:participant, account: account, event: event, govt_id: "GID-1")
      other = create(:participant, account: account, event: event, govt_id: "GID-2")

      other.govt_id = "GID-1"

      expect(other).not_to be_valid
      expect(other.errors[:govt_id]).to be_present
    end

    it "allows the same govt_id in a different event" do
      create(:participant, account: account, event: event, govt_id: "GID-1")
      other_event = create(:event, account: account)
      other = create(:participant, account: account, event: other_event, govt_id: "GID-2")

      other.govt_id = "GID-1"

      expect(other).to be_valid
    end
  end

  describe "EventLiveStats (requirement.md §8)" do
    it "seeds the row and increments registered_count on create" do
      expect(event.event_live_stats).to be_nil

      create(:participant, account: account, event: event)

      expect(event.reload.event_live_stats.registered_count).to eq(1)
    end

    it "keeps incrementing an already-seeded row" do
      create(:participant, account: account, event: event)
      create(:participant, account: account, event: event)

      expect(event.reload.event_live_stats.registered_count).to eq(2)
    end
  end

  # Phase 13 — Communications (requirement.md §3.10): routes through Notifier/
  # NotificationDeliveryJob now, not a bare `ParticipantMailer.confirmation(...).deliver_later` —
  # have_enqueued_mail (an ActionMailer-specific matcher) no longer applies, since
  # NotificationDeliveryJob calls `.deliver_now` synchronously *inside* itself rather than
  # enqueueing ActionMailer's own delivery job; asserting on the tracked Notification row plus
  # NotificationDeliveryJob directly is what actually proves a send happened.
  describe "registration confirmation email (Event Basic Info gap-fill: 'send email on registration?')" do
    include ActiveJob::TestHelper

    it "tracks and enqueues an email Notification when the event's toggle is on and the participant has an email" do
      event.update!(send_registration_email: true)

      expect {
        create(:participant, account: account, event: event, email: "alice@example.com")
      }.to have_enqueued_job(NotificationDeliveryJob)

      notification = Notification.email.last
      expect(notification.to).to eq("alice@example.com")
      expect(notification.status).to eq("pending")
    end

    it "sends nothing when the event's toggle is off (the default)" do
      expect(event.send_registration_email?).to be false

      expect {
        create(:participant, account: account, event: event, email: "alice@example.com")
      }.not_to change { Notification.count }
    end

    it "sends nothing when the participant has no email, even with the toggle on" do
      event.update!(send_registration_email: true)

      expect {
        create(:participant, account: account, event: event, email: nil)
      }.not_to change { Notification.count }
    end
  end

  # Phase 13 — Communications, revisited: "Quick Email Send" — QuickEmailSendJob calls this
  # directly, once per participant; same tracked-send shape as #deliver_confirmation_email above.
  describe "#deliver_quick_email!" do
    include ActiveJob::TestHelper

    let(:email_template) { create(:email_template, account: account, event: event, kind: :quick_send, subject: "Reminder for $EVENT_NAME$") }

    it "tracks and enqueues an email Notification addressed to the participant" do
      participant = create(:participant, account: account, event: event, email: "alice@example.com")

      expect { participant.deliver_quick_email!(email_template) }.to have_enqueued_job(NotificationDeliveryJob)

      notification = Notification.email.last
      expect(notification.to).to eq("alice@example.com")
      expect(notification.status).to eq("pending")
    end

    it "sends nothing when the participant has no email" do
      participant = create(:participant, account: account, event: event, email: nil)

      expect { participant.deliver_quick_email!(email_template) }.not_to change { Notification.count }
    end
  end

  describe "tenant isolation (requirement.md §4.2)" do
    it "never returns another tenant's participants" do
      account_a = create(:account)
      account_b = create(:account)

      Current.account = account_a
      event_a = create(:event, account: account_a)
      create(:participant, account: account_a, event: event_a, first_name: "Account", last_name: "A Participant")

      Current.account = account_b
      event_b = create(:event, account: account_b)
      create(:participant, account: account_b, event: event_b, first_name: "Account", last_name: "B Participant")

      Current.account = account_a
      expect(Participant.count).to eq(1)
      expect(Participant.first.name).to eq("Account A Participant")
    end
  end
end

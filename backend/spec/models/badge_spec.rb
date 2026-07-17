require "rails_helper"

RSpec.describe Badge, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:badge, account: account, event: event)).to be_valid
  end

  describe "uniqueness (requirement.md §5.5: conditional badge layouts by ticket category)" do
    it "allows only one default (no ticket_category) badge per event" do
      create(:badge, account: account, event: event, ticket_category: nil)
      second = build(:badge, account: account, event: event, ticket_category: nil)

      expect(second).not_to be_valid
      expect(second.errors[:base]).to be_present
    end

    it "allows only one badge per ticket_category" do
      category = create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event, ticket_category: category)
      second = build(:badge, account: account, event: event, ticket_category: category)

      expect(second).not_to be_valid
      expect(second.errors[:ticket_category_id]).to be_present
    end

    it "allows a default badge and a category-specific badge on the same event" do
      category = create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event, ticket_category: nil)
      specific = build(:badge, account: account, event: event, ticket_category: category)

      expect(specific).to be_valid
    end

    it "allows the same ticket_category to be reused across different events" do
      other_event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event, ticket_category: category)
      elsewhere = build(:badge, account: account, event: other_event, ticket_category: nil)

      expect(elsewhere).to be_valid
    end
  end

  describe ".build_from_template" do
    it "copies content/mapping/size, not a live reference" do
      template = create(:badge_template, account: account, content: "<div>$NAME$</div>", mapping: { "OTHER1" => "company" }, width_cm: 9, height_cm: 6)

      badge = Badge.build_from_template(template, event: event)

      expect(badge.badge_template).to eq(template)
      expect(badge.content).to eq("<div>$NAME$</div>")
      expect(badge.mapping).to eq({ "OTHER1" => "company" })
      expect(badge.width_cm).to eq(9)
      expect(badge.height_cm).to eq(6)

      badge.save!
      template.update!(content: "<div>changed</div>")
      expect(badge.reload.content).to eq("<div>$NAME$</div>")
    end

    it "assigns the given ticket_category" do
      template = create(:badge_template, account: account)
      category = create(:ticket_category, account: account, event: event)

      badge = Badge.build_from_template(template, event: event, ticket_category: category)

      expect(badge.ticket_category).to eq(category)
    end
  end

  # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12): "whatever
  # fields are placed on a ticket category's badge design are automatically mandatory on that
  # category's registration form."
  describe "#required_catalog_fields" do
    it "is empty for a badge with no catalog-eligible tokens" do
      badge = build(:badge, account: account, event: event, content: "<div>$NAME$ $GOVT_ID$ $QRCODE$</div>")

      expect(badge.required_catalog_fields).to eq([])
    end

    it "includes position when the badge uses $DESIGNATION$" do
      badge = build(:badge, account: account, event: event, content: "<div>$NAME$ $DESIGNATION$</div>")

      expect(badge.required_catalog_fields).to eq([ "position" ])
    end

    # requirement.md v12 revisit — title/first_name/last_name joined Event::PARTICIPANT_FIELD_CATALOG,
    # so their own direct tokens now have a catalog counterpart too (unlike $NAME$ above, still the
    # derived full name, no directly editable column of its own).
    it "includes title/first_name/last_name when the badge uses their own tokens" do
      badge = build(:badge, account: account, event: event, content: "<div>$TITLE$ $FIRST_NAME$ $LAST_NAME$</div>")

      expect(badge.required_catalog_fields).to contain_exactly("title", "first_name", "last_name")
    end

    # requirement.md v12 revisit — "add photo and document in the default form": photo joined the
    # catalog and $PHOTO$ now maps to it; there's no $DOCUMENT$ token at all (badges don't display
    # documents), so document only ever becomes mandatory via TicketCategory#document_required?.
    it "includes photo when the badge uses $PHOTO$" do
      badge = build(:badge, account: account, event: event, content: "<div>$PHOTO$</div>")

      expect(badge.required_catalog_fields).to eq([ "photo" ])
    end

    it "includes a catalog field mapped to an OTHER slot" do
      badge = build(:badge, account: account, event: event, content: "<div>$OTHER1$</div>", mapping: { "OTHER1" => "company" })

      expect(badge.required_catalog_fields).to eq([ "company" ])
    end

    it "ignores an OTHER slot mapped to a non-catalog field" do
      # hex_id/name/etc. are valid HasBadgeMapping::MAPPABLE_FIELDS values but aren't part of
      # Event::PARTICIPANT_FIELD_CATALOG — nothing for a registration form to require.
      badge = build(:badge, account: account, event: event, content: "<div>$OTHER1$</div>", mapping: { "OTHER1" => "hex_id" })

      expect(badge.required_catalog_fields).to eq([])
    end

    it "combines and dedupes fields from content tokens and mapping" do
      badge = build(:badge, account: account, event: event,
        content: "<div>$DESIGNATION$ $OTHER1$ $OTHER2$</div>",
        mapping: { "OTHER1" => "company", "OTHER2" => "position" })

      expect(badge.required_catalog_fields).to contain_exactly("position", "company")
    end
  end
end

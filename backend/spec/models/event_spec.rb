require "rails_helper"

RSpec.describe Event, type: :model do
  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:event, account: account)).to be_valid
  end

  it "requires a name" do
    event = build(:event, account: account, name: nil)
    expect(event).not_to be_valid
    expect(event.errors[:name]).to be_present
  end

  it "requires ends_at to be after starts_at" do
    event = build(:event, account: account, starts_at: 2.days.from_now, ends_at: 1.day.from_now)
    expect(event).not_to be_valid
    expect(event.errors[:ends_at]).to be_present
  end

  describe "mode-dependent location presence" do
    it "requires address for on_site" do
      event = build(:event, account: account, mode: :on_site, address: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:address]).to be_present
    end

    it "requires meeting_link for virtual" do
      event = build(:event, account: account, mode: :virtual, address: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:meeting_link]).to be_present
    end

    it "requires both address and meeting_link for hybrid" do
      event = build(:event, account: account, mode: :hybrid, address: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:address]).to be_present
      expect(event.errors[:meeting_link]).to be_present
    end

    it "is valid for virtual with only a meeting_link" do
      event = build(:event, account: account, mode: :virtual, address: nil, meeting_link: "https://example.com/room")
      expect(event).to be_valid
    end
  end

  describe "slug (friendly_id, scoped per account)" do
    it "generates a slug from the name on create" do
      event = create(:event, account: account, name: "Annual Meetup")
      expect(event.slug).to eq("annual-meetup")
    end

    it "allows the same slug to be reused by a different account" do
      other_account = create(:account)
      create(:event, account: account, name: "Annual Meetup")

      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Annual Meetup")

      expect(other_event.slug).to eq("annual-meetup")
    end

    it "disambiguates a second event with the same name within the same account" do
      create(:event, account: account, name: "Annual Meetup")
      second = create(:event, account: account, name: "Annual Meetup")

      expect(second.slug).not_to eq("annual-meetup")
      expect(second.slug).to start_with("annual-meetup")
    end
  end

  describe "participant_fields jsonb round-trip" do
    it "persists and reloads an arbitrary hash" do
      event = create(:event, account: account, participant_fields: { "email" => true, "company" => false })
      expect(event.reload.participant_fields).to eq({ "email" => true, "company" => false })
    end

    it "defaults to an empty hash" do
      event = create(:event, account: account)
      expect(event.participant_fields).to eq({})
    end
  end

  describe "#basic_info_complete?" do
    it "is false when required fields are missing" do
      event = build(:event, account: account, name: nil)
      expect(event.basic_info_complete?).to be false
    end

    it "is true once name, dates, and mode-appropriate location are all present" do
      event = build(:event, account: account, mode: :on_site, address: "123 Main St")
      expect(event.basic_info_complete?).to be true
    end

    it "is false for a virtual event with only an address, no meeting_link" do
      event = build(:event, account: account, mode: :virtual, address: "123 Main St", meeting_link: nil)
      expect(event.basic_info_complete?).to be false
    end
  end

  describe "status enum" do
    it "defaults to draft" do
      expect(create(:event, account: account).status).to eq("draft")
    end

    it "exposes the full lifecycle" do
      expect(Event.statuses.keys).to eq(%w[draft up_coming live completed])
    end
  end

  # Phase 0's tenant_scoped_spec.rb: "copy this shape for every real TenantScoped model starting
  # with Event in Phase 4" — same assertions, this time against the real model instead of an
  # anonymous stand-in.
  describe "tenant isolation (requirement.md §4.2)" do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }

    before do
      Current.account = account_a
      create(:event, account: account_a, name: "Account A Event")
      Current.account = account_b
      create(:event, account: account_b, name: "Account B Event")
    end

    it "never returns another tenant's events" do
      Current.account = account_a

      expect(Event.count).to eq(1)
      expect(Event.first.account_id).to eq(account_a.id)
    end

    it "raises with no Current.account and no Current.platform_request set" do
      Current.account = nil

      expect { Event.count }.to raise_error(TenantScoped::MissingTenantContextError)
    end

    it "opens up to every tenant's events under Current.platform_request" do
      Current.account = nil
      Current.platform_request = true

      expect(Event.count).to eq(2)
    end
  end
end

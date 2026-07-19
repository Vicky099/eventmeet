require "rails_helper"

# Agency layer (requirement.md revisit): platform-level, not TenantScoped — Current.account is
# deliberately never set in this file (unlike Quotation/Invoice specs), mirroring Account's own
# spec.
RSpec.describe Agency, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:agency)).to be_valid
  end

  it "requires a positive price_per_event" do
    expect(build(:agency, price_per_event: 0)).not_to be_valid
    expect(build(:agency, price_per_event: -10)).not_to be_valid
  end

  it "requires a supported currency" do
    expect(build(:agency, currency: "XYZ")).not_to be_valid
  end

  it "rejects events_granted below events_used" do
    agency = build(:agency, events_granted: 3, events_used: 5)

    expect(agency).not_to be_valid
    expect(agency.errors[:events_granted]).to be_present
  end

  describe "#events_remaining" do
    it "is the gap between granted and used" do
      agency = build(:agency, events_granted: 5, events_used: 2)

      expect(agency.events_remaining).to eq(3)
    end
  end

  describe "#grant_more!" do
    it "adds to events_granted, never replaces it" do
      agency = create(:agency, events_granted: 5, events_used: 2)

      agency.grant_more!(3)

      expect(agency.reload.events_granted).to eq(8)
    end
  end

  describe "#consume_event_slot!" do
    it "increments events_used by one" do
      agency = create(:agency, events_granted: 5, events_used: 2)

      agency.consume_event_slot!

      expect(agency.reload.events_used).to eq(3)
    end

    it "raises once the pool is exhausted" do
      agency = create(:agency, events_granted: 2, events_used: 2)

      expect { agency.consume_event_slot! }.to raise_error(Agency::NoEventSlotsRemainingError)
      expect(agency.reload.events_used).to eq(2)
    end
  end
end

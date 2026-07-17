require "rails_helper"

RSpec.describe Session, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:session, account: account, event: event)).to be_valid
  end

  it "requires a name" do
    expect(build(:session, account: account, event: event, name: nil)).not_to be_valid
  end

  it "requires ends_at after starts_at" do
    session = build(:session, account: account, event: event, starts_at: 2.hours.from_now, ends_at: 1.hour.from_now)
    expect(session).not_to be_valid
    expect(session.errors[:ends_at]).to be_present
  end

  describe "seat_limit (requirement.md §3.8: per-session seat capacity)" do
    it "is valid when nil (unlimited)" do
      expect(build(:session, account: account, event: event, seat_limit: nil)).to be_valid
    end

    it "requires a positive integer when present" do
      expect(build(:session, account: account, event: event, seat_limit: 0)).not_to be_valid
      expect(build(:session, account: account, event: event, seat_limit: -1)).not_to be_valid
      expect(build(:session, account: account, event: event, seat_limit: 1.5)).not_to be_valid
      expect(build(:session, account: account, event: event, seat_limit: 10)).to be_valid
    end
  end

  describe "#unlimited?" do
    it "is true when seat_limit is nil" do
      expect(build(:session, account: account, event: event, seat_limit: nil)).to be_unlimited
    end

    it "is false when seat_limit is set" do
      expect(build(:session, account: account, event: event, seat_limit: 5)).not_to be_unlimited
    end
  end

  describe "#live_stats!" do
    it "lazily seeds a SessionLiveStats row on first use" do
      session = create(:session, account: account, event: event)
      expect(session.session_live_stats).to be_nil

      stats = session.live_stats!

      expect(stats).to be_persisted
      expect(session.reload.session_live_stats).to eq(stats)
    end
  end
end

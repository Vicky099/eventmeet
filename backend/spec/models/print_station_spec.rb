require "rails_helper"

RSpec.describe PrintStation, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe "#online?" do
    it "is false with no paired agent" do
      station = create(:print_station, account: account, event: event)
      expect(station).not_to be_online
    end

    it "is true with a recently-connected, non-revoked agent" do
      station = create(:print_station, :online, account: account, event: event)
      expect(station).to be_online
    end

    it "is false once the agent is revoked" do
      station = create(:print_station, :online, account: account, event: event)
      station.current_agent.update!(revoked_at: Time.current)
      expect(station).not_to be_online
    end

    it "is false once the agent's last_seen_at is stale" do
      station = create(:print_station, :online, account: account, event: event)
      station.current_agent.update!(last_seen_at: 1.hour.ago)
      expect(station).not_to be_online
    end
  end

  describe "#generate_pairing_code!" do
    it "sets a code with a future expiry" do
      station = create(:print_station, account: account, event: event)
      code = station.generate_pairing_code!

      expect(code).to be_present
      expect(station.reload.pairing_code).to eq(code)
      expect(station).to be_pairing_code_active
    end

    it "invalidates a previously issued code" do
      station = create(:print_station, account: account, event: event)
      first_code = station.generate_pairing_code!
      station.generate_pairing_code!

      expect(station.reload.pairing_code).not_to eq(first_code)
    end
  end
end

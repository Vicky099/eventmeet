require "rails_helper"

# Agency → Tenant account switch (requirement.md revisit: "agency will controlled all the event
# using single sign-in as switch account"). Mirrors PrintStation#generate_pairing_code!'s own
# spec shape — a short-lived, single-use, globally unique handoff token.
RSpec.describe AccountSwitch do
  describe ".generate_for" do
    it "creates a switch with a unique token and a 60-second expiry" do
      account = create(:account)
      user = create(:user)

      switch = AccountSwitch.generate_for(user: user, account: account)

      expect(switch).to be_persisted
      expect(switch.token).to be_present
      expect(switch.user).to eq(user)
      expect(switch.account).to eq(account)
      expect(switch.expires_at).to be_within(2.seconds).of(60.seconds.from_now)
      expect(switch.redeemed_at).to be_nil
    end

    it "never collides with an existing token" do
      account = create(:account)
      user = create(:user)
      existing = AccountSwitch.generate_for(user: user, account: account)

      allow(SecureRandom).to receive(:urlsafe_base64).and_return(existing.token, "a-fresh-token")

      switch = AccountSwitch.generate_for(user: user, account: account)

      expect(switch.token).to eq("a-fresh-token")
    end
  end

  describe "#redeemable?" do
    it "is true for a fresh, unexpired, unredeemed switch" do
      switch = create(:account_switch)
      expect(switch).to be_redeemable
    end

    it "is false once expired" do
      switch = create(:account_switch, expires_at: 1.second.ago)
      expect(switch).not_to be_redeemable
    end

    it "is false once redeemed" do
      switch = create(:account_switch)
      switch.redeem!
      expect(switch).not_to be_redeemable
    end
  end

  describe "#redeem!" do
    it "sets redeemed_at, keeping the row as an audit trail rather than destroying it" do
      switch = create(:account_switch)

      switch.redeem!

      expect(switch.redeemed_at).to be_present
      expect(AccountSwitch.exists?(switch.id)).to be true
    end
  end
end

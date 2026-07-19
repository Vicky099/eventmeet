require "rails_helper"

# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Same shape as
# AccountSwitch's own spec (spec/models/account_switch_spec.rb) — a short-lived, single-use,
# globally unique handoff token, minted by a Super Admin instead of self-serve.
RSpec.describe ImpersonationToken do
  describe ".generate_for" do
    it "creates a token with a unique value and a 60-second expiry" do
      platform_staff = create(:user, :platform_staff)
      account = create(:account)
      user = create(:user)

      token = ImpersonationToken.generate_for(platform_staff: platform_staff, user: user, account: account)

      expect(token).to be_persisted
      expect(token.token).to be_present
      expect(token.platform_staff).to eq(platform_staff)
      expect(token.user).to eq(user)
      expect(token.account).to eq(account)
      expect(token.expires_at).to be_within(2.seconds).of(60.seconds.from_now)
      expect(token.redeemed_at).to be_nil
    end

    it "never collides with an existing token" do
      platform_staff = create(:user, :platform_staff)
      account = create(:account)
      user = create(:user)
      existing = ImpersonationToken.generate_for(platform_staff: platform_staff, user: user, account: account)

      allow(SecureRandom).to receive(:urlsafe_base64).and_return(existing.token, "a-fresh-token")

      token = ImpersonationToken.generate_for(platform_staff: platform_staff, user: user, account: account)

      expect(token.token).to eq("a-fresh-token")
    end
  end

  describe "#redeemable?" do
    it "is true for a fresh, unexpired, unredeemed token" do
      token = create(:impersonation_token)
      expect(token).to be_redeemable
    end

    it "is false once expired" do
      token = create(:impersonation_token, expires_at: 1.second.ago)
      expect(token).not_to be_redeemable
    end

    it "is false once redeemed" do
      token = create(:impersonation_token)
      token.redeem!
      expect(token).not_to be_redeemable
    end
  end

  describe "#redeem!" do
    it "sets redeemed_at, keeping the row as an audit trail rather than destroying it" do
      token = create(:impersonation_token)

      token.redeem!

      expect(token.redeemed_at).to be_present
      expect(ImpersonationToken.exists?(token.id)).to be true
    end
  end
end

# Agency → Tenant account switch (requirement.md revisit: "agency will controlled all the event
# using single sign-in as switch account"). A short-lived, single-use handoff token — same shape
# PrintStation#generate_pairing_code! already established for "hand off a privileged action to an
# otherwise-unauthenticated context": globally unique, retry-until-unique SecureRandom, consumed
# (never reused) on redemption.
#
# Not TenantScoped, no RLS — platform-level, like Agency/Account themselves. Created from
# AgencyConsole::AccountsController#switch, where Current.agency is set and Current.account is
# nil; a TenantScoped default_scope would raise MissingTenantContextError on .create here, the
# same reason Invoice dropped TenantScoped for its own agency-contract rows.
class AccountSwitch < ApplicationRecord
  TTL = 60.seconds

  belongs_to :user
  belongs_to :account

  def self.generate_for(user:, account:)
    token = nil
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break unless AccountSwitch.exists?(token: token)
    end

    create!(user: user, account: account, token: token, expires_at: TTL.from_now)
  end

  def redeemable?
    redeemed_at.nil? && expires_at.future?
  end

  def redeem!
    update!(redeemed_at: Time.current)
  end
end

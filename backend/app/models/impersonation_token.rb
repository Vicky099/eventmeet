# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md: "reuse AccountSwitch's
# exact mechanics rather than re-deriving them"). Same shape as AccountSwitch (short-lived,
# single-use, globally unique retry-until-unique SecureRandom, consumed on redemption) — the real
# difference is who mints one (a Super Admin, not a self-serve agency admin) and what has to
# survive redemption: the redeeming controller stashes platform_staff_id into the tenant session
# (not this record) so the "who's really behind this" identity persists for the whole impersonated
# visit, not just the one redirect AccountSwitch's own handoff needs.
#
# Not TenantScoped, no RLS — platform-level, like AccountSwitch/Agency/Account themselves.
class ImpersonationToken < ApplicationRecord
  TTL = 60.seconds

  belongs_to :platform_staff, class_name: "User"
  belongs_to :user
  belongs_to :account

  def self.generate_for(platform_staff:, user:, account:)
    token = nil
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break unless ImpersonationToken.exists?(token: token)
    end

    create!(platform_staff: platform_staff, user: user, account: account, token: token, expires_at: TTL.from_now)
  end

  def redeemable?
    redeemed_at.nil? && expires_at.future?
  end

  def redeem!
    update!(redeemed_at: Time.current)
  end
end

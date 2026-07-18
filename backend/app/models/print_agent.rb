# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3, §8). One row
# per successfully-redeemed pairing — the credential record a station-scoped JWT's `agent_id`
# claim resolves to. Revocation is enforced by re-checking `revoked_at` here on every connect/
# subscribe, never by trusting the token's own expiry alone (requirement.md: "revocable per
# station at any time... immediately invalidating its JWT").
class PrintAgent < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :print_station

  validates :jti, presence: true, uniqueness: true

  def revoked?
    revoked_at.present?
  end

  def online?
    connected? && last_seen_at.present? && last_seen_at > PrintStation::ONLINE_WINDOW.ago
  end
end

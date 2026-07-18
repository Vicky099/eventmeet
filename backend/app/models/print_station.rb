# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). The admin-facing
# "desk" (Station A → Printer 1) — created from the admin console before any Electron agent has
# ever paired to it. Pairing itself (PrintAgent) is a separate model since a station accumulates
# pairing history over its life (revoke, then re-pair) rather than being 1:1 with a device.
class PrintStation < ApplicationRecord
  include TenantScoped

  PAIRING_CODE_TTL = 10.minutes
  # requirement.md: "connection-status indicator per paired station (online/offline via Cable
  # presence)." Cable disconnects aren't always cleanly delivered (a killed process, a dropped
  # network), so #online? also requires a heartbeat/subscribe within this window, not just the
  # `connected` flag PrintJobsChannel's subscribed/unsubscribed toggles.
  ONLINE_WINDOW = 45.seconds

  belongs_to :event
  has_many :print_agents, dependent: :destroy
  has_many :print_jobs, dependent: :destroy
  has_many :bulk_print_runs, dependent: :destroy

  validates :name, presence: true

  # The most recent non-revoked pairing — a station can have several PrintAgent rows over its
  # life (revoke, then re-pair later); this is "whichever one is actually live right now."
  def current_agent
    print_agents.where(revoked_at: nil).order(paired_at: :desc).first
  end

  def online?
    agent = current_agent
    agent.present? && agent.connected? && agent.last_seen_at.present? && agent.last_seen_at > ONLINE_WINDOW.ago
  end

  def pairing_code_active?
    pairing_code.present? && pairing_code_expires_at.present? && pairing_code_expires_at.future?
  end

  # Globally unique (PrintAgentsController#pair looks it up before any tenant is known — see
  # that migration's own comment) — same retry-until-unique shape Participant#generate_unique_hex_id
  # already establishes. Regenerating implicitly invalidates whatever code was there before,
  # since it's a single column, not an append-only list — exactly one pairing attempt is ever
  # meaningful per station at a time.
  def generate_pairing_code!
    code = nil
    loop do
      code = SecureRandom.alphanumeric(8).upcase
      break unless PrintStation.unscoped_across_tenants { PrintStation.exists?(pairing_code: code) }
    end

    update!(pairing_code: code, pairing_code_expires_at: PAIRING_CODE_TTL.from_now)
    code
  end
end

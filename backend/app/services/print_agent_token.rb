# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3). The
# station-scoped JWT a paired Electron agent authenticates its Action Cable connection and its
# badge-PDF fetch with. Signed with Rails' own secret_key_base — this app's existing
# general-purpose signing secret (already what Rails itself uses for cookies/CSRF), not a new
# credential to provision just for this.
#
# Claims: account_id/event_id/station_id (what the agent is scoped to, requirement.md: "one agent
# = one tenant + one event/station, never a platform-wide credential"), agent_id (the PrintAgent
# row, for the live revocation check below), jti (this token's own id).
#
# Expiry is short-ish but NOT the actual revocation mechanism — an agent just reconnects with a
# fresh token issued at pairing time; the real, immediate revocation path is
# PrintAgent#revoked_at, re-checked on every #decode call here so a revoked agent is rejected
# well before its token would otherwise expire (requirement.md: "revocable... immediately
# invalidating its JWT").
class PrintAgentToken
  ALGORITHM = "HS256"
  TTL = 24.hours

  DecodeError = Class.new(StandardError)

  def self.encode(print_agent)
    new.encode(print_agent)
  end

  def self.decode(token)
    new.decode(token)
  end

  def encode(print_agent)
    payload = {
      account_id: print_agent.account_id,
      event_id: print_agent.event_id,
      station_id: print_agent.print_station_id,
      agent_id: print_agent.id,
      jti: print_agent.jti,
      exp: TTL.from_now.to_i
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  # Returns the live, non-revoked PrintAgent the token claims to be, or nil — every caller
  # (ApplicationCable::Connection, PrintAgentController#badge) treats nil the same way: reject.
  def decode(token)
    return nil if token.blank?

    payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM)
    agent = PrintAgent.unscoped_across_tenants { PrintAgent.find_by(id: payload["agent_id"], jti: payload["jti"]) }
    return nil if agent.nil? || agent.revoked?

    agent
  rescue JWT::DecodeError
    nil
  end

  private

  def secret
    Rails.application.secret_key_base
  end
end

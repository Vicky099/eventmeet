# Phase 9 — standard Rails Action Cable scaffolding, not generated until now since nothing used
# Action Cable before this phase (requirement.md §5.15). Identifies via Warden directly rather
# than Devise's own connection helpers, since this app runs two independent Warden scopes on one
# User class (:user for the tenant Admin Console, :platform_staff for the Platform Console — see
# config/routes.rb) and a cable connection needs to accept either, whichever the browser tab
# opening it happens to be signed in as.
#
# This is the connection-level authorization floor only (must be signed in as *something*) —
# Turbo::StreamsChannel's own signed stream names (derived from the page that rendered
# `turbo_stream_from`) are what keep a subscriber to one event's live stats from also being able
# to guess another tenant's; per-record authorization at the channel layer isn't added on top,
# same trust model the rest of the app already places in page-level Pundit checks.
#
# Phase 10 revisit — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3): a
# paired Electron agent has no Devise session at all (it's a background daemon on a front-desk
# machine, not a signed-in browser tab), so it can't satisfy find_verified_user. Rather than
# mounting a second ActionCable::Server (this app only ever mounts one, config/routes.rb), the
# same connection now accepts a *second*, independent identity: a station-scoped JWT passed as
# `?token=...` on the cable URL, verified against the live, non-revoked PrintAgent it claims to
# be (PrintAgentToken.decode — the actual revocation check happens there, not here). #connect
# tries the existing browser/Warden path first (unchanged, non-rejecting), then falls back to the
# print-agent token; only rejects if neither resolves to anything.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_print_agent

    def connect
      self.current_user = find_verified_user
      self.current_print_agent = find_verified_print_agent

      reject_unauthorized_connection if current_user.nil? && current_print_agent.nil?
    end

    private

    def find_verified_user
      warden = request.env["warden"]
      warden.user(:user) || warden.user(:platform_staff)
    end

    def find_verified_print_agent
      PrintAgentToken.decode(request.params[:token])
    end
  end
end

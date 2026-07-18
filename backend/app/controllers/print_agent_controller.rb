# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3). The
# Electron agent's own two HTTP touchpoints — everything else (receiving print jobs, reporting
# status) happens over the PrintJobsChannel Action Cable connection instead. Deliberately not
# under Admin:: (no Devise session exists here — the agent is a background daemon on a front-desk
# machine, not a signed-in browser tab) but still routed under the tenant subdomain constraint
# (mirrors CheckinController's "include exactly what's needed, skip authenticate_user!" shape),
# so Current.account still comes from the Host the same way it does for every other tenant-scoped
# request — the agent connects to the same `{tenant_slug}.{platform_domain}.com` its pairing code
# was generated on, never a bare/ambiguous host.
class PrintAgentController < ApplicationController
  include TenantResolvable

  # Confirmed live (a real POST from a bare HTTP client, no browser session, 500'd with
  # ActionController::InvalidAuthenticityToken before this was added — request specs didn't
  # catch it because Rails' test environment disables forgery protection by default). The
  # Electron agent has no session cookie to carry a CSRF token in the first place — this
  # endpoint's real credentials are the one-time pairing code (#pair) and the station-scoped
  # Bearer JWT (#badge), the same non-cookie-based auth model every other JSON API in this app
  # not reachable from a browser session already goes without CSRF protection for.
  skip_before_action :verify_authenticity_token

  before_action :authenticate_agent!, only: :badge

  # requirement.md: "authenticates to the platform with a station-scoped pairing token." The
  # pairing code itself is the one-time credential here — looked up scoped to the tenant the
  # request actually arrived on (Current.account, set by TenantResolvable above), never a
  # cross-tenant guess, same "Host is the only source of truth" rule every other tenant-scoped
  # endpoint in this app follows.
  def pair
    station = Current.account.print_stations.find_by(pairing_code: params[:pairing_code])

    if station.nil? || !station.pairing_code_active?
      render json: { error: "Invalid or expired pairing code." }, status: :unprocessable_content
      return
    end

    agent = station.print_agents.create!(account: Current.account, event: station.event, jti: SecureRandom.uuid, paired_at: Time.current)
    station.update!(pairing_code: nil, pairing_code_expires_at: nil)

    render json: {
      token: PrintAgentToken.encode(agent),
      cable_url: ActionCable.server.config.url || request.base_url.sub(/^http/, "ws") + "/cable",
      station_name: station.name,
      event_name: station.event.name
    }
  end

  # GET print_agent/print_jobs/:id/badge — the agent fetches the rendered PDF for a job it was
  # just pushed over the channel. Authorization is the Bearer JWT only (not the pairing code,
  # already consumed) — reuses BadgePdfService unchanged, same renderer the admin console's own
  # on-demand download already uses.
  def badge
    job = @print_agent.print_station.print_jobs.find_by(id: params[:id])
    return head :not_found if job.nil?

    badge = job.event.badge_for(job.participant)
    return head :not_found if badge.nil?

    pdf = BadgePdfService.render(badge: badge, participant: job.participant)
    send_data pdf, filename: "badge-#{job.participant.hex_id}.pdf", type: "application/pdf", disposition: "inline"
  end

  private

  def authenticate_agent!
    token = request.authorization.to_s.delete_prefix("Bearer ").presence
    @print_agent = PrintAgentToken.decode(token)

    # Defense in depth beyond the JWT's own account_id claim (requirement.md §4.3: "never trust a
    # client-supplied tenant ID — Host is the only source of truth") — a token issued for one
    # tenant must never be honored on a different tenant's subdomain, even if it somehow arrived
    # there.
    head :unauthorized if @print_agent.nil? || @print_agent.account_id != Current.account&.id
  end
end

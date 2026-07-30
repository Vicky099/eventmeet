# Phase 25 — Public Event Site API (doc/public_event_site_options.md). Rails → Next.js on-demand
# ISR invalidation — same role/shape GupshupClient already takes for an outbound platform-level
# integration credential (plain Net::HTTP, ENV-driven config, never raises past its own
# boundary — the caller, PublicSiteRevalidationJob, decides what "failed" means here). Unlike
# GupshupClient, a missing URL is the *expected*, common case (no Next.js deployment configured
# yet, e.g. every dev/test environment) — silently skipped, not logged as a failure; only a
# configured-but-unreachable target logs a warning, since there's no Notification-style row here
# to mark failed and nothing durable would be lost by a missed cache invalidation (the 5-minute
# `revalidate: 300` TTL, doc's own "Caching" section, is the fallback either way).
class PublicSiteRevalidator
  def self.call(event)
    new.call(event)
  end

  def call(event)
    url = ENV["PUBLIC_SITE_REVALIDATE_URL"]
    return if url.blank?

    uri = URI(url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "X-Revalidate-Secret" => ENV["PUBLIC_SITE_REVALIDATE_SECRET"].to_s)
    # Event's own slug is only unique per account (`friendly_id :name, use: :scoped, scope:
    # account_id`) — two different tenants can have the same slug at once, so the tag has to carry
    # the account too, or one tenant's content change would spuriously invalidate a same-slug
    # event belonging to someone else. Must exactly match the shape Next.js's own
    # lib/server/rails.ts#eventCacheTag builds — kept in one place there, mirrored here in prose
    # since this is the one call site on the Ruby side that needs to agree with it.
    request.body = { tag: "event:#{event.account.subdomain_slug}:#{event.slug}" }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    Rails.logger.warn("[PublicSiteRevalidator] #{uri} returned #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    Rails.logger.warn("[PublicSiteRevalidator] request to #{url} failed: #{e.class}: #{e.message}")
  end
end

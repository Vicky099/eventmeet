# Phase 25 — Public Event Site API (doc/public_event_site_options.md). Backgrounded so an
# Event/EventPage save is never blocked on an outbound HTTP call to Next.js (same
# "never block a request on a slow/down external call" reasoning NotificationDeliveryJob already
# establishes for Gupshup/mail sends) — PublicSiteRevalidator itself never raises, so there's
# nothing here to rescue/retry.
class PublicSiteRevalidationJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.unscoped_across_tenants { Event.find_by(id: event_id) }
    return if event.nil?

    PublicSiteRevalidator.call(event)
  end
end

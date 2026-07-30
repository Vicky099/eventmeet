# Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2/#4).
# One row per Event (has_one on that side), holding the raw HTML that event's own admin pastes for
# its public page — stored and rendered exactly as submitted, deliberately no sanitization (that
# event's own admin owns the risk for their own page/visitors, not a cross-tenant concern, same
# trust model a website builder's "custom code" feature takes). Saving it never touches the
# event's own status/published_at — no draft/publish workflow of its own.
class EventPage < ApplicationRecord
  include TenantScoped

  belongs_to :event

  validates :event_id, uniqueness: true

  # Phase 25 — Public Event Site API (doc/public_event_site_options.md) — Event's own identical
  # hook covers publish state/CONTENT_ATTRIBUTES; this covers the other half of what the public
  # event-show response actually returns, content_html itself.
  after_commit :notify_public_site_change

  private

  def notify_public_site_change
    PublicSiteRevalidationJob.perform_later(event_id)
  end
end

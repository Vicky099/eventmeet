# Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2/#4).
# One row per Event (has_one on that side), holding the raw HTML that event's own admin pastes for
# its public page — stored and rendered exactly as submitted, deliberately no sanitization (that
# event's own admin owns the risk for their own page/visitors, not a cross-tenant concern, same
# trust model a website builder's "custom code" feature takes). Saving it never touches the
# event's own status/published_at — no draft/publish workflow of its own.
class EventPage < ApplicationRecord
  include TenantScoped

  # doc/event_page_templates_plan.md, Stage 1 — nil (the column's own default) still means exactly
  # what it always has, "Custom HTML" (the `html` column above/below), not a new state. Only set
  # once an agency admin actually picks one of the eventics designs (AgencyConsole::EventPagesController).
  # requirement.md revisit (direct user instruction, three passes): "Remove template 4 completely
  # ... as it is not fit with event" (auction/marketplace demo, nothing was assigned it — plain
  # removal), "keep the template number in serial. 1,2,3,4" (renumbered the former Template 5 down
  # to fill the gap), then "Remove template 3 completely ... keep the numbering serial again" —
  # this pass. Template 3 (a nightclub/multi-event-venue demo design) is gone the same way
  # Template 4 was, except an event *was* actually assigned it this time, so removal alone wasn't
  # enough — db/migrate/*_remove_template3_renumber_template4_to3.rb both reassigns that row (onto
  # the design replacing this slot) and renumbers the former Template 4 down to Template 3, in one
  # migration. See that migration's own comment for the exact two-step integer shuffle.
  enum :template_key, { template_1: 0, template_2: 1, template_3: 2 }

  belongs_to :event

  validates :event_id, uniqueness: true

  # doc/event_page_templates_plan.md, Stage 3 — the resolution rule for the two ways this record
  # can render a public page: a numbered template always wins over stored Custom HTML, so the two
  # are never simultaneously "live." Picking a template from AgencyConsole::EventPagesController's
  # dropdown blanks out `html` at save time — one-directional only, deliberately: switching back to
  # "Custom HTML" afterward starts from a blank textarea rather than silently resurrecting
  # whatever was there before the template was chosen (simpler to reason about than reviving stale
  # content the agency admin already moved away from).
  before_validation :clear_html_when_template_selected

  # Phase 25 — Public Event Site API (doc/public_event_site_options.md) — Event's own identical
  # hook covers publish state/CONTENT_ATTRIBUTES; this covers the other half of what the public
  # event-show response actually returns, content_html itself.
  after_commit :notify_public_site_change

  private

  def clear_html_when_template_selected
    self.html = "" if template_key.present?
  end

  def notify_public_site_change
    PublicSiteRevalidationJob.perform_later(event_id)
  end
end

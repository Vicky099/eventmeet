# Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2, §8). The first real model to include
# TenantScoped (app/models/concerns/tenant_scoped.rb) and Postgres RLS (lib/
# tenant_row_level_security.rb, db/migrate/*_create_events.rb) — both built in Phase 0 for
# exactly this moment.
class Event < ApplicationRecord
  include TenantScoped

  # requirement.md §5.4/§3.4 (Phase 7's Participant model doesn't exist yet — this is purely a
  # declarative "which fields will be required" config until then): the fixed catalog Phase 4
  # ships with. Phase 7 generalizes this into a real custom-field builder; until then the Basic
  # Info tab just toggles these on/off into participant_fields.
  PARTICIPANT_FIELD_CATALOG = %w[email contact_num company department position nationality country].freeze

  extend FriendlyId
  # :scoped (not a bare :slugged) — two different tenants must each be able to use, say,
  # "annual-meetup" as their own event's slug (requirement.md §4.2 tenant isolation applies to
  # human-facing identifiers too, not just IDs). scope: :account_id, not :account — avoids
  # loading the association just to compute a scope column. Slug uniqueness generation itself
  # queries through TenantScoped's default_scope safely — FriendlyId::Scoped bypasses it via
  # `.unscoped` internally but immediately re-applies an equivalent account_id filter from the
  # scope column, so it never actually leaks another tenant's rows.
  friendly_id :name, use: :scoped, scope: :account_id

  enum :mode, { on_site: 0, virtual: 1, hybrid: 2 }
  # requirement.md §3.2: "Draft/Upcoming/Live/Completed lifecycle, auto-transitioned by
  # schedule" — EventSchedulerJob (app/jobs/event_scheduler_job.rb) is the only thing that ever
  # moves a *published* Event off `draft`; an event that has never been published (published_at
  # nil) is invisible to that job and stays `draft` indefinitely regardless of its schedule. See
  # `publish!` / `published_at` below — the wizard's Review step is what calls it.
  enum :status, { draft: 0, up_coming: 1, live: 2, completed: 3 }
  # Independent of `status` above (requirement.md §5.2, workflow built in Phase 5). `unsubmitted`
  # (schema default) is the real starting state — an event only becomes `pending` (and so only
  # shows up in SuperAdmin::EventReviewsController's queue) once the organizer explicitly calls
  # `submit_for_review!` from the Review step; that method also handles the reject → edit →
  # resubmit cycle back into `pending`.
  enum :approval_status, { pending: 0, approved: 1, rejected: 2, unsubmitted: 3 }
  enum :banner_orientation, { landscape: 0, portrait: 1 }

  # requirement.md §5.2: "typically reviewed within 24 hours" — the review queue's own SLA
  # target, plus how far out from breaching it the queue starts visually flagging an item.
  REVIEW_SLA = 24.hours
  REVIEW_SLA_WARNING_WINDOW = 4.hours

  # What the wizard's Next buttons actually persist per step so far (only Basic Info has real
  # fields until later phases fill in Agenda/Tickets/Badge) — also what
  # `revert_to_draft_if_published_content_changed` watches to decide whether a save counts as
  # "content changed" (and so should un-publish) versus a status-only write from
  # EventSchedulerJob or `publish!` itself.
  CONTENT_ATTRIBUTES = %w[name mode starts_at ends_at address meeting_link map_url banner_orientation participant_fields].freeze

  has_many :event_staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :event_staff_assignments, source: :user
  # The Super Admin who approved it (SuperAdmin::EventReviewsController#approve) — optional since
  # it's nil for the whole unsubmitted/pending/rejected lifetime, not just historically before
  # Phase 5.
  belongs_to :approved_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :starts_at, :ends_at, presence: true
  validates :rejection_reason, presence: true, if: :rejected?
  validate :ends_at_after_starts_at
  validate :location_present_for_mode

  before_save :revert_to_draft_if_published_content_changed

  # Drives the Basic Info step's completeness indicator (requirement.md Phase 4: "each tab shows
  # its own completeness indicator") — the same presence/mode rules as the validations above,
  # read-only (no side effects), so it's safe to call from a view on every render rather than
  # only after a failed save. Also gates whether the Review step's Publish button is enabled.
  def basic_info_complete?
    return false if name.blank? || starts_at.blank? || ends_at.blank?

    case mode
    when "on_site" then address.present?
    when "virtual" then meeting_link.present?
    when "hybrid" then address.present? && meeting_link.present?
    else false
    end
  end

  def published?
    published_at.present?
  end

  # Same schedule math EventSchedulerJob ticks on — factored out here so `publish!` can put a
  # freshly-published event into the *correct* status immediately, instead of leaving it `draft`
  # until the job's next run (up to RESCHEDULE_INTERVAL later).
  def computed_status(now = Time.current)
    return "completed" if ends_at && now >= ends_at
    return "live" if starts_at && now >= starts_at

    "up_coming"
  end

  # The wizard Review step's Publish action. A raw mutation, deliberately without a
  # basic_info_complete? guard — that business rule belongs to the controller action
  # (Admin::EventsController#publish), not the model.
  def publish!
    update!(published_at: Time.current, status: computed_status)
  end

  # Phase 5 (requirement.md §5.2, §4.7 item 2): the organizer's explicit "submit for approval"
  # action from the Review step — the only thing that ever moves an event out of `unsubmitted`
  # (or back out of `rejected`) into `pending`, which is what puts it in
  # SuperAdmin::EventReviewsController's queue for the first time. Stamps a fresh `submitted_at`
  # and clears whatever the previous review left behind. Deliberately doesn't touch
  # `status`/`published_at` — approval and publish/schedule state are independent axes
  # (requirement.md §5.2), and `revert_to_draft_if_published_content_changed` already handles the
  # "edited after publish" side of that on its own.
  def submit_for_review!
    update!(approval_status: :pending, submitted_at: Time.current, rejection_reason: nil, approved_by: nil, approved_at: nil)
  end

  # SuperAdmin::EventReviewsController#approve. requirement.md §5.2 v8: "re-approval on edit" —
  # once approved, further edits do NOT revert this (unlike `status`/`published_at`, which
  # `revert_to_draft_if_published_content_changed` does reset) — billing is per event, not
  # content-gated, so there's nothing here that needs to watch CONTENT_ATTRIBUTES the way that
  # callback does.
  def approve!(by:)
    update!(approval_status: :approved, approved_by: by, approved_at: Time.current)
  end

  # SuperAdmin::EventReviewsController#reject — `reason` is required (validates :rejection_reason,
  # presence: true, if: :rejected? above); the event stays otherwise untouched and editable, and
  # the organizer sees the reason via `submit_for_review!`'s resubmit path.
  def reject!(reason:)
    update!(approval_status: :rejected, rejection_reason: reason)
  end

  # Whether this event's review is close to or past requirement.md §5.2's 24h SLA — drives the
  # review queue's visual flag. Only meaningful while actually pending; an approved/rejected event
  # isn't "at risk" of anything anymore.
  def review_sla_at_risk?
    pending? && submitted_at.present? && Time.current >= submitted_at + REVIEW_SLA - REVIEW_SLA_WARNING_WINDOW
  end

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end

  def location_present_for_mode
    case mode
    when "on_site"
      errors.add(:address, "can't be blank for an on-site event") if address.blank?
    when "virtual"
      errors.add(:meeting_link, "can't be blank for a virtual event") if meeting_link.blank?
    when "hybrid"
      errors.add(:address, "can't be blank for a hybrid event") if address.blank?
      errors.add(:meeting_link, "can't be blank for a hybrid event") if meeting_link.blank?
    end
  end

  # "if event is published and edited anything then change the event status to draft again" —
  # fires on any save to an already-published event that touches a CONTENT_ATTRIBUTES field.
  # Guarded by published_at_changed? so it doesn't fight `publish!`'s own write (which changes
  # published_at itself, not content) or a bare EventSchedulerJob status-only update (which
  # changes neither).
  def revert_to_draft_if_published_content_changed
    return unless persisted?
    return unless published_at_in_database.present?
    return if published_at_changed?
    return if (changed & CONTENT_ATTRIBUTES).empty?

    self.status = "draft"
    self.published_at = nil
  end
end

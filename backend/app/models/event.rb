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
  # title/first_name/last_name added in Phase 7.5 (requirement.md v12 revisit — "title, firstname
  # & lastname in the default fields selection"): previously always-rendered/unconditionally
  # positioned at the top of the manual-entry form, outside any catalog config at all; joining the
  # catalog is what makes them selectable and orderable in the registration form builder the same
  # way every other field already is. first_name stays *effectively* required regardless of
  # whatever an organizer configures — see TicketCategory#effective_catalog_fields and
  # Participant's own unconditional `validates :first_name, presence: true` — a participant needs
  # some name; only its position (and title/last_name's requiredness) is genuinely configurable.
  # photo/document added in the same v12 revisit ("add photo and document in the default form") —
  # same treatment as everything else: catalog-toggleable/orderable, `.attached?`-checked instead
  # of `.blank?` (see Participant#required_fixed_fields_present). `document`'s pre-existing
  # ticket_category-level requirement (TicketCategory#document_required?) is folded into
  # #effective_catalog_fields as another forced-true source, same as first_name/badge-mandated
  # fields, rather than staying a second, independent validation with its own error message.
  PARTICIPANT_FIELD_CATALOG = %w[title first_name last_name email contact_num company department position nationality country photo document].freeze

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
  CONTENT_ATTRIBUTES = %w[name description mode starts_at ends_at address meeting_link map_url banner_orientation participant_fields has_seat_limit seat_limit participant_approval_required is_paid send_registration_email].freeze

  has_many :event_staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :event_staff_assignments, source: :user
  # Phase 6 — Ticketing (requirement.md §5.3). Nested attributes, not individually-saved rows —
  # the Tickets step builds up categories in one form the same way Basic Info does, only actually
  # persisted on that step's own Next click (Admin::EventsController#update).
  # reject_if: :all_blank skips a row nobody touched (the "Add another category" template row, if
  # never filled in and never explicitly removed either).
  has_many :ticket_categories, dependent: :destroy
  accepts_nested_attributes_for :ticket_categories, allow_destroy: true, reject_if: :all_blank
  # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Standalone,
  # named forms an organizer builds once and assigns to whichever TicketCategory rows should use
  # them (TicketCategory#belongs_to :registration_form), including all of them at once — see
  # RegistrationForm's own model comment. Supersedes Phase 7's event-level `custom_fields`/
  # `accepts_nested_attributes_for :custom_fields` (CustomField now `belongs_to
  # :registration_form`, not `:event`) — organizer-defined fields live on a form now, not one list
  # for the whole event. `participant_fields`/`PARTICIPANT_FIELD_CATALOG` (below) are unused for
  # enforcement at this point (superseded by RegistrationForm#catalog_fields via
  # TicketCategory#effective_catalog_fields) but stay real columns/constants — the catalog names
  # themselves are still what RegistrationForm's own catalog_fields hash is keyed against.
  has_many :registration_forms, dependent: :destroy
  has_many :participants, dependent: :destroy
  # Phase 9 — Check-in, Attendance & Real-Time Live Dashboards (requirement.md §3.7, §5.15).
  # event_id is a denormalized column on both (partitioned) tables, so these are direct read
  # associations for the check-in kiosk's "recent scans" list and EventCompletionService's
  # end-of-event sweep — not `dependent: :destroy`. Actual destroy-time protection for scan/
  # attendance history lives on Participant#scan_events/#attendances (restrict_with_error), which
  # this Event's own `has_many :participants, dependent: :destroy` already routes through.
  has_many :scan_events
  has_many :attendances
  has_one :event_live_stats, dependent: :destroy
  has_many :import_files, dependent: :destroy
  has_many :export_files, dependent: :destroy
  # requirement.md revisit: "we will upload that [government ID] list, this will be stored in
  # database somewhere." GovtId's own dependent handling of a participant is a plain FK column,
  # not an association here — see db/migrate/20260717160017_create_govt_ids.rb.
  has_many :govt_ids, dependent: :destroy
  has_many :govt_id_import_files, dependent: :destroy
  # Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). At most one default (no
  # ticket_category) plus at most one per TicketCategory — see Badge's own uniqueness validation
  # and the partial unique indexes backing it.
  has_many :badges, dependent: :destroy
  # Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8, §5.6). dependent: :destroy on
  # both — unlike Participant, a Session/Schedule carries no data worth protecting on its own
  # (Session's own has_many :scan_events/:attendances is what actually guards real check-in
  # history from being silently lost, the same restrict_with_error shape Participant uses).
  has_many :sessions, dependent: :destroy
  # :schedules destroyed before :speakers (declaration order) — Speaker's own has_many :schedules
  # is restrict_with_error, so a speaker cascading-destroyed while still holding schedules would
  # otherwise block the whole Event destroy; clearing schedules first leaves nothing to restrict.
  has_many :schedules, dependent: :destroy
  has_many :speakers, dependent: :destroy
  # The Super Admin who approved it (SuperAdmin::EventReviewsController#approve) — optional since
  # it's nil for the whole unsubmitted/pending/rejected lifetime, not just historically before
  # Phase 5.
  belongs_to :approved_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :starts_at, :ends_at, presence: true
  validates :rejection_reason, presence: true, if: :rejected?
  # Once "This event has a seat limit" is toggled on, seat_limit stops being optional — a toggle
  # that's on but has no actual number attached to it isn't a meaningful state.
  validates :seat_limit, presence: true, if: :has_seat_limit?
  validate :ends_at_after_starts_at
  validate :location_present_for_mode
  validate :ticket_categories_within_seat_limit
  validate :destroyed_categories_have_no_participants

  # The Tickets step's "This event has a seat limit" toggle CSS-hides the seat_limit field (still
  # present in the DOM, just not rendered) rather than removing it, so a stale value can still
  # arrive in params after the organizer switches the toggle back off. Clearing it here — before
  # validation, not before_save — is what makes ticket_categories_within_seat_limit correctly see
  # "no limit" in that case instead of validating against a number the form no longer shows.
  before_validation :clear_seat_limit_unless_flagged
  # Same reasoning, one level down: each ticket category's own "Total seats" column is CSS-hidden
  # by the very same toggle (requirement.md §5.3 revisit — a category's capacity only exists as a
  # concept once the event has a seat limit at all), so a stale total_count on an existing
  # category needs clearing too, not just the event's own seat_limit.
  before_validation :clear_category_total_counts_unless_seat_limited
  before_save :revert_to_draft_if_published_content_changed

  # Drives the Basic Info step's completeness indicator (requirement.md Phase 4: "each tab shows
  # its own completeness indicator") — the same presence/mode rules as the validations above,
  # read-only (no side effects), so it's safe to call from a view on every render rather than
  # only after a failed save. Also gates whether the Review step's Publish button is enabled.
  def basic_info_complete?
    return false if name.blank? || starts_at.blank? || ends_at.blank?

    case mode
    when "on_site" then address.present? && map_url.present?
    when "virtual" then meeting_link.present?
    when "hybrid" then address.present? && map_url.present? && meeting_link.present?
    else false
    end
  end

  # Wizard stepper's green-checkmark state (app/views/admin/events/edit.html.erb) — a lightweight
  # "does this step have real content yet" check per step, not full validation (each step's own
  # form/basic_info_complete? already enforces that where it matters); good enough for an
  # at-a-glance progress indicator. Sessions/Speaker/Event Schedule/Tickets/Badge are all
  # optional, so "complete" here just means "at least one row exists," not "every field filled
  # in." Review's own completion is the wizard's actual terminal action (Publish), not a content
  # check.
  def step_complete?(step)
    case step
    when "basic_info" then basic_info_complete?
    when "sessions" then sessions.exists?
    when "speaker" then speakers.exists?
    when "event_schedule" then schedules.exists?
    when "tickets" then ticket_categories.exists?
    when "badge" then badges.exists?
    when "review" then published?
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

  # The wizard Review step's Publish action — the tenant's own, manual, and only reachable once a
  # Super Admin has approved (requirement.md §5.2 revisited: Publish used to be independent of
  # approval; now it's gated behind it — see Admin::EventsController#publish, which is where that
  # `approved?` check actually lives, same "controller pre-checks the business rule, model method
  # is a raw mutation" split basic_info_complete? already gets there).
  def publish!
    update!(published_at: Time.current, status: computed_status)
  end

  # Phase 5 (requirement.md §5.2, §4.7 item 2): the organizer's explicit "submit for approval"
  # action from the Review step — the only thing that ever moves an event out of `unsubmitted`
  # (or back out of `rejected`) into `pending`, which is what puts it in
  # SuperAdmin::EventReviewsController's queue for the first time. Stamps a fresh `submitted_at`
  # and clears whatever the previous review left behind. Deliberately doesn't touch
  # `status`/`published_at` — publish! is a distinct, later, manual step the tenant takes once
  # approved (see #publish! above), and `revert_to_draft_if_published_content_changed` already
  # handles the "edited after publish" side of the schedule/draft cycle on its own.
  def submit_for_review!
    update!(approval_status: :pending, submitted_at: Time.current, rejection_reason: nil, approved_by: nil, approved_at: nil)
  end

  # SuperAdmin::EventReviewsController#approve. A raw approval only — it does NOT publish the
  # event; that's the tenant's own subsequent manual action, unlocked (not performed) by this
  # (Admin::EventsController#publish requires approved? now). requirement.md §5.2 v8:
  # "re-approval on edit" — once approved, further edits do NOT revert this (unlike
  # `status`/`published_at`, which `revert_to_draft_if_published_content_changed` does reset) —
  # billing is per event, not content-gated, so there's nothing here that needs to watch
  # CONTENT_ATTRIBUTES the way that callback does.
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

  # Phase 7 (requirement.md §5.4): what a brand-new Participant's status should start as —
  # `Admin::ParticipantsController`/`ParticipantImportJob` both call this rather than each
  # re-deriving the same `participant_approval_required?` branch.
  def default_participant_status
    participant_approval_required? ? :pending : :confirmed
  end

  # Seeded lazily on first use (Phase 7 checklist: "EventLiveStats row seeded/incremented on
  # participant create") rather than at Event creation time — most of an event's life happens
  # before it has a single participant, so there's no reason every Event needs one from birth.
  # find_or_create_by! (not find_or_create_by, and not a `has_one` autosave default) because this
  # is called from Participant's own after_create — a silently-nil stats row there would just
  # swallow the very count it exists to keep.
  def live_stats!
    event_live_stats || create_event_live_stats!(account: account)
  end

  # requirement.md revisit ("Registered, Checked In, Arrived Today & Currently In Venue values
  # are not respect the registered one"): the single source of truth for every check-in reporting
  # number both admin/scan_events/_live_stats.html.erb and admin/events/show.html.erb display —
  # previously duplicated inline in the scan_events partial alone. Deliberately NOT
  # EventLiveStats#checked_in_count/#occupancy_count — those are cumulative *scan* counters (a
  # participant checking in twice counts twice, correct for that model's own real-time-counter
  # concerns) which is exactly why they could read higher than a real headcount once the same
  # person got scanned more than once; every method here counts *distinct participants* instead,
  # naturally bounded by #participants.count. Event-level only (session_id: nil) throughout —
  # matches EventLiveStats' own scope (ScanService#apply_counters!'s own comment: a session
  # check-in never touches EventLiveStats).
  def checked_in_participant_count
    participants.joins(:scan_events).merge(ScanEvent.check_in.where(session_id: nil)).distinct.count
  end

  def arrived_today_participant_count
    participants.joins(:scan_events)
      .merge(ScanEvent.check_in.where(session_id: nil, scanned_at: Time.zone.today.all_day))
      .distinct.count
  end

  # Not simply checked_in - checked_out (that only holds up if nobody's ever checked in twice
  # without an intervening check-out — untrue in general); the correct read is each participant's
  # own *most recent* event-level scan — in venue only if that scan was a check-in.
  def currently_in_venue_count
    latest_event_level_scan_by_participant.values.count(&:check_in?)
  end

  # requirement.md revisit: "add graph to show hour, day wise check-in ... admin should
  # understand how many participant came event in realtime." Grouped in Ruby off a plain `.pluck`
  # (not a raw SQL EXTRACT(HOUR FROM ...)/DATE(...), which would bucket by the *stored* value's
  # own zone, not this app's configured Time.zone — `scanned_at` already comes back
  # zone-aware-cast to Time.zone via ActiveRecord, so `.hour`/`.to_date` on the Ruby object is the
  # only way this doesn't silently drift to UTC bucketing on a non-UTC deployment). Bounded to one
  # event's own check-in history — at most a few hundred rows, not a scale where pushing this into
  # SQL would matter.
  def hourly_checkin_counts(date: Time.zone.today)
    scan_events.check_in.where(session_id: nil, scanned_at: date.all_day).pluck(:scanned_at).group_by(&:hour).transform_values(&:count)
  end

  def daily_checkin_counts
    scan_events.check_in.where(session_id: nil).pluck(:scanned_at).map(&:to_date).tally
  end

  # #currently_in_venue_count's own building block — each participant's most recent event-level
  # check_in/check_out, keyed by participant_id. Ordering ascending then keeping the last row per
  # group is the plain-Ruby equivalent of a `DISTINCT ON (participant_id) ... ORDER BY scanned_at
  # DESC` window query — not worth the raw-SQL/Postgres-specific trade-off at this row count.
  # Public (not currently_in_venue_count's own private helper) — ParticipantExportJob's own
  # "Currently In Venue" column reuses this exact same computation rather than a second copy of
  # the same group_by/transform_values.
  def latest_event_level_scan_by_participant
    scan_events.where(scan_type: [ :check_in, :check_out ], session_id: nil)
      .order(:scanned_at).group_by(&:participant_id).transform_values(&:last)
  end

  # Phase 8 (requirement.md §5.5: "conditional badge layouts by ticket category... without
  # duplicating templates") — a participant's own ticket category's badge wins if one exists,
  # otherwise the event's default (no ticket_category) badge, otherwise nil (nothing configured
  # yet). The PDF-download endpoint and any future print-agent job (Phase 10) call this; it's a
  # thin wrapper over #badge_for_category below, which is the one place the actual resolution
  # logic lives.
  def badge_for(participant)
    badge_for_category(participant.ticket_category)
  end

  # Phase 7.5 (requirement.md §5.4/§5.14 v12) — #badge_for's own category-then-default fallback,
  # factored out to accept a TicketCategory directly rather than only ever through a Participant:
  # TicketCategory#effective_catalog_fields needs "this category's own badge" to compute the
  # badge-mandatory rule before any Participant of that category exists yet.
  def badge_for_category(ticket_category)
    return nil if badges.empty?

    badges.find { |badge| badge.ticket_category_id == ticket_category&.id } ||
      badges.find { |badge| badge.ticket_category_id.nil? }
  end

  private

  # "capacity validated against event-level seat limit if one is set" (Phase 6 checklist,
  # requirement.md §5.3) — lives here, not on TicketCategory, specifically so it sees every
  # category in *this* save, including ones nested-attributes just built in memory and hasn't
  # persisted yet. `ticket_categories` is the loaded in-memory association at this point (nested
  # attributes assignment loads it to match existing rows by id) — summing over it in Ruby, not a
  # fresh `.sum(:total_count)` SQL query, is what makes several brand-new categories submitted
  # together in one Tickets-step "Next" actually see each other's totals.
  def ticket_categories_within_seat_limit
    return if seat_limit.blank?

    total = ticket_categories.reject(&:marked_for_destruction?).sum { |category| category.total_count.to_i }
    return if total <= seat_limit

    errors.add(:seat_limit, "can't be less than the combined total seats (#{total}) across this event's ticket categories")
  end

  # Runs before any destroy is actually attempted (this is a normal `validate`, not a
  # before_destroy callback) so removing a category with existing participants fails cleanly
  # through the same "re-render with errors" path every other Tickets-step mistake already takes,
  # instead of reaching TicketCategory's own `dependent: :restrict_with_error` guard — which,
  # called through accepts_nested_attributes_for's nested-destroy machinery, raises
  # ActiveRecord::RecordNotDestroyed (an unhandled 500) rather than degrading gracefully the way
  # it does when a record's own #destroy is called directly. That association-level guard stays as
  # defense-in-depth for any future direct-destroy path; this validation is what actually protects
  # the one path that exists today.
  def destroyed_categories_have_no_participants
    ticket_categories.select(&:marked_for_destruction?).each do |category|
      next unless category.persisted? && category.participants.exists?

      errors.add(:base, "Can't remove \"#{category.name}\" — participants are already registered under it.")
    end
  end

  def clear_seat_limit_unless_flagged
    self.seat_limit = nil unless has_seat_limit?
  end

  # Iterates the in-memory association (not a query) so it sees categories nested-attributes just
  # built in this same save, same reasoning as ticket_categories_within_seat_limit above — a
  # category added in the very request that also turns the toggle off should still get cleared,
  # not just ones that already existed beforehand.
  def clear_category_total_counts_unless_seat_limited
    return if has_seat_limit?

    ticket_categories.each { |category| category.total_count = nil }
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end

  # Basic Info mandatory-field rules: on-site needs both Address and a Google Maps link
  # (map_url — previously optional everywhere, now required alongside address for on-site/
  # hybrid); virtual needs a meeting link; hybrid needs all three.
  def location_present_for_mode
    case mode
    when "on_site"
      errors.add(:address, "can't be blank for an on-site event") if address.blank?
      errors.add(:map_url, "can't be blank for an on-site event") if map_url.blank?
    when "virtual"
      errors.add(:meeting_link, "can't be blank for a virtual event") if meeting_link.blank?
    when "hybrid"
      errors.add(:address, "can't be blank for a hybrid event") if address.blank?
      errors.add(:map_url, "can't be blank for a hybrid event") if map_url.blank?
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

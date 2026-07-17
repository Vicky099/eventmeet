# Phase 6 — Ticketing (requirement.md §5.3, §8). Capacity bucket only — no price field, no
# checkout, in line with the "free/RSVP-style, capacity limits only" scope note. TenantScoped +
# RLS from day one (same pattern Phase 4 established for Event/EventStaffAssignment).
class TicketCategory < ApplicationRecord
  include TenantScoped

  belongs_to :event
  has_many :ticket_reservations, dependent: :destroy
  # Unlike ticket_reservations, participants must NOT cascade-delete just because their category
  # gets removed from the event-setup wizard — restrict_with_error turns what would otherwise be
  # a raw ActiveRecord::InvalidForeignKey (PG rejecting the DELETE, an unhandled 500) into a clean
  # validation error the Tickets step's nested-attributes save already knows how to display.
  has_many :participants, dependent: :restrict_with_error
  # Unlike participants, a category-specific Badge (Phase 8) is just display configuration, not
  # data worth protecting — safe to cascade-delete along with the category itself.
  has_many :badges, dependent: :destroy
  # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). A standalone
  # RegistrationForm the organizer assigns to this category (Admin::RegistrationFormsController) —
  # optional: nil means unassigned, falling back to RegistrationForm::BUILTIN_DEFAULT_CATALOG (see
  # #effective_catalog_fields below). The *same* form can be any number of categories'
  # registration_form_id at once — "apply to every category" is just assigning it to all of them,
  # not a separate concept — so unlike Badge there's no uniqueness to enforce here at all.
  belongs_to :registration_form, optional: true

  validates :name, presence: true
  # total_count only exists at all once the parent Event has a seat limit (requirement.md §5.3
  # revisit) — the Tickets step hides the "Total seats" column entirely otherwise, and
  # Event#clear_category_total_counts_unless_seat_limited nils it out server-side to match. A
  # category with no total_count is "unlimited": no capacity tracked, reservations always
  # succeed (see TicketReservationService), nothing to waitlist against.
  validates :total_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :total_count, presence: true, if: -> { event&.has_seat_limit? }
  # "capacity validated against event-level seat limit if one is set" (Phase 6 checklist) lives on
  # Event, not here — see Event#ticket_categories_within_seat_limit. A per-category validation
  # comparing against `event.ticket_categories.where.not(id: id).sum(:total_count)` looked right
  # but was actually broken: that's a fresh SQL query, so when several *new* categories are
  # submitted together in one nested-attributes save (the Tickets step's own "Next" batch), none
  # of them can see each other yet — each validates against zero already-*persisted* siblings and
  # passes individually even though their combined total blows the limit. Event validates the
  # in-memory association instead, which does include unsaved siblings from the same batch.

  # Keeps remain_count correct on every direct save of this row — plain creation (remain_count
  # otherwise defaults to the schema's 0, wrongly showing a brand-new category as already full)
  # and editing total_count (raising/lowering it must move remain_count by the same amount,
  # not leave it stale at whatever it was before). This does NOT fire when a sibling
  # TicketReservation changes — TicketReservationService calls #sync_counts! explicitly for that,
  # since saving a reservation doesn't itself touch/save this row.
  before_save :sync_remain_count

  # Ports the baseline's `Event#sync_tickets`: sold_count/remain_count are derived from this
  # category's own reservations, never written directly by a controller — called after any
  # TicketReservationService mutation (create/cancel/promote) so the stored counts never drift
  # from what the reservations actually say. update_columns (not save) deliberately: this fires
  # mid-request, in response to a *different* record changing, not a user editing this one — no
  # reason to re-run this row's own validations/callbacks for a write that only ever touches
  # already-valid derived columns.
  def sync_counts!
    seats = reserved_seat_count
    update_columns(sold_count: seats, remain_count: total_count.nil? ? nil : total_count.to_i - seats)
  end

  # An "unlimited" category (no total_count — see the validation above) has no remaining-seats
  # ceiling to check against; every reservation succeeds outright.
  def unlimited?
    total_count.nil?
  end

  # Phase 7.5 — the union that actually drives fixed-field requiredness: whatever the organizer
  # configured on #registration_form (or RegistrationForm::BUILTIN_DEFAULT_CATALOG when there's no
  # form at all yet), with every catalog field this category's own badge displays
  # (Event#badge_for_category → Badge#required_catalog_fields) forced to `true` — "whatever's on
  # the badge is mandatory on the form," enforced here rather than left for the organizer to
  # notice and check by hand — plus two more unconditional forces: `first_name` (a participant
  # needs *some* name no matter what's configured, mirrored by Participant's own unconditional
  # `validates :first_name, presence: true` as the real backstop) and `document`, but only when
  # this category's own `#document_required?` says so (folds that pre-existing, independent
  # ticket_category-level requirement into the same mechanism rather than leaving it a second
  # validation with its own separate error message). Keeping both of these forces here — not just
  # in the model validation — is what keeps the manual-entry form's own asterisk/`required`
  # attribute from disagreeing with what's actually enforced. Same hash shape the old
  # Event#participant_fields had (every Event::PARTICIPANT_FIELD_CATALOG key present, boolean
  # value), so callers don't need to know which source it actually came from.
  def effective_catalog_fields
    base = registration_form&.catalog_fields ||
      Event::PARTICIPANT_FIELD_CATALOG.index_with { |field| RegistrationForm::BUILTIN_DEFAULT_CATALOG.include?(field) }
    badge_fields = event.badge_for_category(self)&.required_catalog_fields || []
    forced = { "first_name" => true }
    forced["document"] = true if document_required?

    base.merge(badge_fields.index_with { true }).merge(forced)
  end

  # requirement.md v12 revisit: "position each and every field — order of the field should be
  # configurable." No form assigned falls back to the catalog's own plain declared order, same
  # "no context configured yet" shape #effective_catalog_fields already uses for its own fallback.
  def ordered_catalog_fields
    registration_form&.ordered_catalog_fields || Event::PARTICIPANT_FIELD_CATALOG
  end

  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... same parameter should be used while importing the data." nil (not
  # RegistrationForm::UNIQUENESS_FIELDS' full list) when there's no form assigned, or an
  # already-existing form nobody has resaved since this feature shipped (uniqueness_fields still
  # its pre-migration default of []) — Participant.duplicate_match's own `uniqueness_fields: nil`
  # default is what actually falls back to its original, unconditional govt ID -> email+name ->
  # email -> phone cascade, so this deliberately hands that decision to the one place it's already
  # implemented rather than re-declaring "both fields" as a second default here.
  def effective_uniqueness_fields
    registration_form&.uniqueness_fields&.presence
  end

  private

  def reserved_seat_count
    new_record? ? 0 : ticket_reservations.reserved.sum(:seat_count)
  end

  def sync_remain_count
    self.sold_count = reserved_seat_count
    self.remain_count = total_count.nil? ? nil : total_count.to_i - sold_count.to_i
  end
end

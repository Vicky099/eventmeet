# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). A standalone,
# named registration form belonging to an Event — organizer builds one (name + catalog fields +
# custom fields) independent of any ticket category, then assigns it to whichever categories
# should use it (TicketCategory#belongs_to :registration_form), including all of them at once
# ("apply to every category" is just assigning the same form to every category, not a special
# nil/default form of its own — see Admin::RegistrationFormsController). A category left
# unassigned (registration_form_id: nil) falls back to BUILTIN_DEFAULT_CATALOG below; there's no
# other "default form" concept to model.
class RegistrationForm < ApplicationRecord
  include TenantScoped

  # TicketCategory#effective_catalog_fields' fallback for a category with no RegistrationForm
  # assigned at all — so an unassigned category never has literally zero fields to register with.
  # Every Event::PARTICIPANT_FIELD_CATALOG entry (title/first_name/last_name aren't in this list
  # at all — they're always-collected core Participant columns, unconditionally rendered/required
  # independent of any catalog, see Participant#required_fixed_fields_present and
  # admin/participants/_form.html.erb's own top section — so there's nothing for this constant to
  # add for them). Not a smaller, "just enough to reach a registrant" subset — the built-in
  # default is meant to look and behave like a real, complete registration form on its own, not a
  # bare minimum placeholder.
  BUILTIN_DEFAULT_CATALOG = Event::PARTICIPANT_FIELD_CATALOG.dup.freeze

  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... unique by email, unique by contact num or both ... same parameter should be used while
  # importing the data." The organizer's own dedupe config for whichever ticket categories use
  # this form — TicketCategory#effective_uniqueness_fields resolves it, and both Participant
  # #not_a_duplicate (manual entry) and ParticipantImportJob (bulk upload) funnel through the same
  # Participant.duplicate_match with it, so neither path can disagree about what counts as a
  # duplicate for a given category.
  UNIQUENESS_FIELDS = %w[email contact_num].freeze

  belongs_to :event
  # dependent: :nullify, not :restrict_with_error/:destroy — deleting a form an organizer no
  # longer wants shouldn't destroy the ticket categories that happened to be using it, nor should
  # it be blocked just because some are; they simply fall back to BUILTIN_DEFAULT_CATALOG, same as
  # any other unassigned category.
  has_many :ticket_categories, dependent: :nullify
  # Phase 7.5 (requirement.md §5.4/§5.14 v12) — rescoped from Event#custom_fields; same
  # batch-build-then-save-on-Next nested-attributes shape, only the owner changed.
  has_many :custom_fields, -> { order(:position) }, dependent: :destroy
  accepts_nested_attributes_for :custom_fields, allow_destroy: true, reject_if: :all_blank

  # Names matter now that an event can have several forms coexisting (assigned to different
  # categories, or waiting to be assigned) — nothing enforced this when there was at most one
  # per-category form plus one unnamed default/shared form.
  validates :name, presence: true
  # requirement.md revisit: "At least one uniqueness parameter should be set" — presence works
  # directly against the plain jsonb array (`[].blank?` is true, same as any other Ruby Array),
  # no custom emptiness check needed. The inclusion check is defense-in-depth against a tampered
  # request param — Admin::RegistrationFormsController#registration_form_params already
  # intersects the submitted array against UNIQUENESS_FIELDS before it ever reaches here.
  validates :uniqueness_fields, presence: { message: "select at least one field to detect duplicates by" }
  validate :uniqueness_fields_recognized

  # Reader override, not an after_initialize callback — a callback only fires once, at
  # construction, so it can't paper over a *partial* hash assigned later via a plain `catalog_fields
  # = {...}`/`update!(catalog_fields: {...})` (exactly how FactoryBot's attribute-by-attribute
  # assignment sets it, and how a real controller update will too). Recomputing on every read
  # instead guarantees every Event::PARTICIPANT_FIELD_CATALOG key is always present — whichever
  # keys the stored value doesn't have default to false — regardless of how the raw column got
  # its value or when this is called (a freshly-built record, right after assignment, or loaded
  # back from the DB all behave identically). `super` reads the raw underlying jsonb value.
  def catalog_fields
    Event::PARTICIPANT_FIELD_CATALOG.index_with { false }.merge(super)
  end

  # Same reader-override reasoning as #catalog_fields above (recomputes on every read, not just
  # at construction, so a later partial assignment can't leave a key missing) — default position
  # is each field's own index in Event::PARTICIPANT_FIELD_CATALOG, so an organizer who never
  # touches ordering still gets the catalog's natural order, not an arbitrary one.
  def catalog_field_positions
    Event::PARTICIPANT_FIELD_CATALOG.each_with_index.to_h.merge(super)
  end

  # requirement.md v12 revisit: "position each and every field — order of the field should be
  # configurable." The one place both the builder and the actual manual-entry form
  # (admin/participants/_form.html.erb, via TicketCategory#ordered_catalog_fields) read from, so
  # they can never disagree about display order. Only orders the fixed catalog — CustomField
  # ordering is its own #position column + RegistrationForm#custom_fields' own `order(:position)`
  # scope, already real, just never had a UI to set it meaningfully until now.
  def ordered_catalog_fields
    Event::PARTICIPANT_FIELD_CATALOG.sort_by { |field| catalog_field_positions[field] }
  end

  private

  def uniqueness_fields_recognized
    unrecognized = Array(uniqueness_fields) - UNIQUENESS_FIELDS
    return if unrecognized.empty?

    errors.add(:uniqueness_fields, "includes an unrecognized field: #{unrecognized.to_sentence}")
  end
end

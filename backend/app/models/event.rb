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
  # moves an Event off `draft`; there is no separate manual "publish" action in this phase.
  enum :status, { draft: 0, up_coming: 1, live: 2, completed: 3 }
  # Independent of `status` above (requirement.md §5.2) — column only this phase, the review
  # workflow (approved_by, approved_at, rejection_reason, the SuperAdmin queue) is Phase 5.
  enum :approval_status, { pending: 0, approved: 1, rejected: 2 }
  enum :banner_orientation, { landscape: 0, portrait: 1 }

  has_many :event_staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :event_staff_assignments, source: :user

  validates :name, presence: true
  validates :starts_at, :ends_at, presence: true
  validate :ends_at_after_starts_at
  validate :location_present_for_mode

  # Drives the Basic Info tab's completeness indicator (requirement.md Phase 4: "each tab shows
  # its own completeness indicator") — the same presence/mode rules as the validations above,
  # read-only (no side effects), so it's safe to call from a view on every render rather than
  # only after a failed save.
  def basic_info_complete?
    return false if name.blank? || starts_at.blank? || ends_at.blank?

    case mode
    when "on_site" then address.present?
    when "virtual" then meeting_link.present?
    when "hybrid" then address.present? && meeting_link.present?
    else false
    end
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
end

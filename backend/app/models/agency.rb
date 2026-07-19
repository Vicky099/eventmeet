# Sits above the tenant boundary, same as Account itself — platform-level, not TenantScoped, no
# account_id. Since the fixed-hierarchy pivot (requirement.md revisit, confirmed with the user:
# "super admin will create the agency and agency will create the tenants"), an Agency is also a
# real subdomain-hosted console of its own (AgencyConsole::BaseController, TenantResolvable's own
# comment) — the only place a new tenant Account is ever created (AgencyConsole::AccountsController,
# AccountProvisioning's own agency: kwarg), with every event on those tenants created with no
# per-event Quotation/content-review round trip at all (Event's own contract-gated validation).
#
# Billing is agency-level, one of two contracts (`billing_cycle`):
#   per_event — a fixed pool of events at one fixed price (events_granted/events_used/
#     price_per_event, unchanged from the original design) — Event#consume_agency_slot_if_metered
#     decrements it per event created.
#   annual — unlimited events for one fixed price, paid in full up front before the agency can
#     create anything at all (#contract_invoice, #contract_active?) — no pool to track.
class Agency < ApplicationRecord
  class NoEventSlotsRemainingError < StandardError; end

  enum :status, { active: 0, suspended: 1 }
  enum :billing_cycle, { per_event: 0, annual: 1 }

  has_many :agency_memberships, dependent: :destroy
  has_many :users, through: :agency_memberships
  # dependent: :nullify, not :destroy — unlinking (or destroying) an Agency must never take a
  # tenant Account and its events/participants down with it.
  has_many :accounts, dependent: :nullify
  # The one upfront lump-sum payment an `annual` agency's contract is gated on
  # (Invoice.generate_for_agency_contract) — `has_one`, not `has_many`, matching "one Invoice per
  # agency contract" the same way Event's own `has_one :invoice` already reads. Always nil for a
  # `per_event` agency (nothing ever creates one).
  has_one :invoice, dependent: :destroy, inverse_of: :agency

  validates :name, presence: true
  # requirement.md §4.3's own RESERVED_SLUGS/format rules, mirrored exactly (Account::RESERVED_SLUGS
  # itself, not a duplicated list) — an Agency subdomain is indistinguishable from a tenant one at
  # the routing layer (Hosting::TenantSubdomainConstraint matches either), so it needs the exact
  # same collision protection against platform routes.
  validates :subdomain_slug, presence: true,
                              uniqueness: { case_sensitive: false },
                              format: {
                                with: /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/,
                                message: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphen"
                              },
                              length: { minimum: 3, maximum: 63 },
                              exclusion: { in: Account::RESERVED_SLUGS, message: "is a reserved word" }
  # Cross-table uniqueness — TenantResolvable's own resolution (Account first, then Agency) needs
  # an unambiguous answer; without this, an Agency could silently claim a slug an Account already
  # has, and would just never be reachable (Account always wins the lookup first), a confusing
  # "the agency exists but 404s forever" bug rather than a validation error at creation time.
  validate :subdomain_slug_not_taken_by_an_account
  validates :currency, inclusion: { in: Currency::CODES }
  # Every per_event-only field becomes conditionally required — an `annual` agency has no pool to
  # speak of (truly unlimited), so price_per_event/events_granted/events_used have nothing
  # meaningful to validate.
  validates :price_per_event, numericality: { greater_than: 0 }, if: :per_event?
  validates :events_granted, numericality: { greater_than_or_equal_to: 0, only_integer: true }, if: :per_event?
  validates :events_used, numericality: { greater_than_or_equal_to: 0, only_integer: true }, if: :per_event?
  validate :events_used_within_granted, if: :per_event?
  validates :annual_price, numericality: { greater_than: 0 }, if: :annual?

  before_validation { self.subdomain_slug = subdomain_slug&.downcase }

  def events_remaining
    events_granted - events_used
  end

  # Super Admin's "top up the pool" action — additive, never a raw edit of events_granted, so it
  # can never accidentally get set below events_used.
  def grant_more!(count)
    update!(events_granted: events_granted + count.to_i)
  end

  # Atomic guarded decrement — same idempotent-race-safety idiom as Event's own
  # quotation_must_be_approved_and_available (a plain in-memory check-then-update can't be trusted
  # under concurrent event creation; this uses a single conditional UPDATE instead). Raises if the
  # pool is already exhausted, which Event's own before_create callback lets bubble up as a normal
  # validation failure (see Event#consume_agency_slot_if_metered).
  def consume_event_slot!
    updated = Agency.where(id: id).where("events_used < events_granted").update_all("events_used = events_used + 1")
    raise NoEventSlotsRemainingError, "No event slots remaining for \"#{name}\"" unless updated == 1

    reload
  end

  # The single gate both AgencyConsole::AccountsController#create (tenant creation) and Event's own
  # create-time validation check: a per_event agency is always "active" (its own pool exhaustion is
  # a separate, per-event concern, not a blanket contract gate); an annual agency needs its one
  # upfront contract Invoice actually marked paid.
  def contract_active?
    per_event? || (annual? && invoice&.paid?)
  end

  private

  def events_used_within_granted
    return if events_granted.blank? || events_used.blank?

    errors.add(:events_granted, "can't be less than events already used (#{events_used})") if events_granted < events_used
  end

  def subdomain_slug_not_taken_by_an_account
    return if subdomain_slug.blank?

    errors.add(:subdomain_slug, "has already been taken") if Account.where("lower(subdomain_slug) = ?", subdomain_slug).exists?
  end
end

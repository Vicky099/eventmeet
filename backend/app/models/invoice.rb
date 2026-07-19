# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
# user). The simplified lifecycle:
#   event completes -> next day InvoiceGenerationJob auto-creates a `draft` Invoice for
#   `event.quotation.current_amount` (no plan tiers/overage math left — Business is the only plan,
#   priced once via its Quotation) -> Super Admin reviews and `#send!`s it -> tenant submits UTR +
#   a receipt via the "Mark as Paid" modal (`#submit_payment!`) -> Super Admin `#verify!`s it
#   (paid) or `#reject_payment!`s it (clears the UTR/receipt "slot" for exactly one resubmission,
#   with a reason the tenant sees).
#
# Fixed-hierarchy pivot (requirement.md revisit): reused, not duplicated, for the new agency-level
# "one upfront annual contract payment" flow (Agency#billing_cycle: annual) —
# Invoice.generate_for_agency_contract raises the same draft/awaiting_payment/under_review/paid +
# UTR/receipt row, just with `agency:` set and `event:`/`account:` both nil instead. Exactly one of
# `event` or `agency` is required (#exactly_one_of_event_or_agency below); the Quotation gate this
# model's own comment used to reference is gone entirely (fixed-hierarchy pivot, no more per-event
# pricing negotiation).
#
# No longer TenantScoped (fixed-hierarchy pivot): an agency-level contract invoice has no
# Current.account to default-scope against at all. Every read site that used to lean on that
# default_scope now filters explicitly — Admin::InvoicesController's own `Invoice.includes(...)`
# gains a `.where(account: Current.account)` (see that controller's own comment).
class Invoice < ApplicationRecord
  include TenantScopedAttachment

  enum :status, { draft: 0, awaiting_payment: 1, under_review: 2, paid: 3 }

  belongs_to :account, optional: true
  belongs_to :event, optional: true
  belongs_to :agency, optional: true, inverse_of: :invoice
  belongs_to :submitted_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  has_one_attached :receipt

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: Currency::CODES }
  validate :exactly_one_of_event_or_agency
  # A light safety net matching the invariant #submit_payment! itself always maintains (utr set
  # together with the status change, same update! call) — not the actual enforcement point.
  # `rejection_reason` has no equivalent status-based check here (unlike Event's own
  # `if: :rejected?` — this model folds "rejected" back into `awaiting_payment` rather than a
  # distinct status, so there's no clean state to hook a presence validation to); the controller
  # guards a blank reason before ever calling #reject_payment!, same "controller pre-checks,
  # model method is a raw mutation" split every other bang-method in this app already takes.
  validates :utr_reference, presence: true, if: :under_review?

  # InvoiceGenerationJob's own entry point — one Invoice, straight from the event's own Agency's
  # current price_per_event/currency (no editable draft-amount step; there's only one number, so
  # there's nothing to review before this besides "is it correct," which is what the Super Admin's
  # own review-before-#send! step is for). Read fresh off `event.account.agency` rather than any
  # value cached on the Event itself: the requirement is "the agency's *current* fixed price," not
  # a snapshot from whenever the event was created, and nothing here needs one — an Invoice is only
  # ever raised once, at completion, well after creation. Never called for an `annual`-billing_cycle
  # agency's events (unlimited, no per-event charge) — InvoiceGenerationJob's own sweep already only
  # targets events with no invoice yet, and an annual agency's events never need one.
  def self.generate_for(event)
    agency = event.account.agency
    event.create_invoice!(account: event.account, amount: agency.price_per_event, currency: agency.currency)
  end

  # Invoices moved to the Agency Console entirely (requirement.md revisit: "we will only charge
  # agency based on contract per event / Per Year" — the agency is who actually pays, so the
  # agency is who manages/pays every invoice, not each individual tenant). Covers both invoice
  # shapes an agency ever has at once: its own single annual-contract Invoice (`agency:` set) and
  # every per-event Invoice across its own tenants (`account:` set) — mutually exclusive in
  # practice (an agency is either `annual`, only ever the former, or `per_event`, only ever the
  # latter), so AgencyConsole::InvoicesController#index shows the right thing per agency with no
  # billing_cycle branch of its own needed.
  def self.for_agency(agency)
    where(agency: agency).or(where(account: agency.accounts))
  end

  # The annual contract's own entry point (AgencyProvisioning, right after creating an
  # `annual`-billing_cycle Agency) — the one upfront lump-sum Invoice gating #contract_active?
  # (Agency's own comment). No `account:`/`event:` — this predates any tenant Account existing at
  # all under the agency.
  def self.generate_for_agency_contract(agency)
    agency.create_invoice!(amount: agency.annual_price, currency: agency.currency)
  end

  def attach_receipt(uploaded_file)
    attach_tenant_scoped(:receipt, uploaded_file, "invoices", event_id || "agency-contract")
  end

  # Super Admin action — the only thing that actually notifies the tenant (BillingMailer, from the
  # controller, not baked in here — same "controller orchestrates, model method is a raw mutation"
  # split every other bang-method in this app takes).
  def send!
    update!(status: :awaiting_payment)
  end

  # Tenant action — the "Mark as Paid" modal. Overwrites any previous (rejected) UTR/receipt —
  # there's only ever one current attempt, not a history of past ones.
  def submit_payment!(utr_reference:, receipt:, by:)
    update!(utr_reference: utr_reference, submitted_by: by, submitted_at: Time.current, status: :under_review)
    attach_receipt(receipt) if receipt.present?
  end

  def verify!(by:)
    update!(status: :paid, verified_by: by, verified_at: Time.current, rejection_reason: nil)
  end

  # Back to awaiting_payment (resubmittable via the same modal) — deliberately does NOT clear
  # `utr_reference`/`receipt`: BillingMailer#payment_rejected reads them to tell the tenant exactly
  # what was rejected, and the next #submit_payment! call overwrites both anyway (one "slot," not a
  # history), so there's no window where a stale value could be mistaken for a fresh submission.
  def reject_payment!(reason:, by:)
    update!(status: :awaiting_payment, rejection_reason: reason, verified_by: by, verified_at: Time.current)
  end

  private

  def exactly_one_of_event_or_agency
    return if event.present? ^ agency.present?

    errors.add(:base, "must belong to exactly one of an event or an agency")
  end

  # TenantScopedAttachment#tenant_scoped_blob_key's own default reads `account` unconditionally —
  # overridden here since an agency-contract Invoice has none; `account || agency` both respond to
  # `#subdomain_slug`, which is all TenantScopedAttachment.blob_key actually needs (duck-typed, same
  # as every other caller established this session).
  def tenant_scoped_blob_key(*segments, filename:)
    TenantScopedAttachment.blob_key(account || agency, *segments, filename: filename)
  end
end
